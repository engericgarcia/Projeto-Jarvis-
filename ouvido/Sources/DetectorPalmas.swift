import Foundation

/// Detector de palmas por análise do envelope do sinal.
///
/// Uma palma tem três marcas que a separam de fala, música e batida de porta:
///   1. ataque abrupto  — o nível salta dezenas de dB em poucos milissegundos;
///   2. decaimento curto — cai de volta em ~100 ms (fala e música sustentam);
///   3. energia em agudos — é um estalo de banda larga, não um "tum" grave.
///
/// O detector exige as três coisas antes de contar uma palma, e depois agrupa
/// palmas próximas no tempo para formar um gesto (2 palmas, 3 palmas...).
final class DetectorPalmas {

    struct Ajustes {
        /// Nível mínimo absoluto para uma palma ser considerada (dBFS).
        var limiarPicoDb: Float = -32
        /// Quanto o nível precisa saltar acima do piso de ruído (dB).
        var saltoOnsetDb: Float = 14
        /// Fração mínima da energia que precisa estar acima de ~2 kHz.
        var razaoAgudosMin: Float = 0.25
        /// Queda exigida depois do pico para confirmar que foi um estalo (dB).
        var decaimentoDb: Float = 9
        /// Quanto o pico precisa superar o nível que havia ANTES do ataque (dB).
        /// É o que separa palma de plosiva: a palma sai do silêncio, o "t" e o
        /// "p" da fala saem do meio da própria fala.
        var preSilencioDb: Float = 20
        /// Quando medir essa queda, contado a partir do ataque (ms).
        var msParaDecair: Double = 130
        /// Tempo morto após uma palma, para não contar o eco dela (ms).
        var refratarioMs: Double = 130
        /// Intervalo válido entre duas palmas do mesmo gesto (ms).
        var janelaMinMs: Double = 90
        var janelaMaxMs: Double = 700
        /// Pausa na detecção depois de disparar um gesto — evita que o som da
        /// própria confirmação (voz/bipe) seja ouvido como palma nova (ms).
        var esperaPosGestoMs: Double = 1800
    }

    /// Chamado quando um gesto completo é reconhecido, com o número de palmas.
    var aoDetectarGesto: ((Int) -> Void)?
    /// Chamado a cada palma confirmada — usado só no modo --debug.
    var aoDetectarPalma: ((Int, Float) -> Void)?
    /// Amostragem periódica de níveis para o modo --debug: (dB, piso, agudos).
    var aoAmostrar: ((Float, Float, Float) -> Void)?

    /// Maior gesto configurado. Ao atingir esse número o disparo é imediato,
    /// sem esperar a janela fechar.
    var maxPalmas: Int = 2
    var ajustes = Ajustes()

    private let taxaAmostragem: Double
    private let tamanhoHop = 256

    // Estado do filtro passa-altas (~2 kHz) usado para medir os agudos.
    private var alfaHP: Float = 0
    private var entradaAnterior: Float = 0
    private var saidaAnterior: Float = 0

    // Histórico curto de níveis, para olhar o que havia antes do ataque.
    private var historico = [Float](repeating: -70, count: 64)
    private var hIndice = 0
    private var preAoOnset: Float = -70

    private var acumulador: [Float] = []
    private var relogio: Double = 0          // segundos de áudio processados
    private var pisoRuido: Float = -60
    private var silencioAte: Double = 0.6    // ignora o primeiro instante (piso instável)

    private enum Estado {
        case ocioso
        case verificando(inicio: Double, pico: Float)
    }
    private var estado: Estado = .ocioso
    private var ultimaPalma: Double = -1
    private var palmas: [Double] = []
    private var contadorAmostras = 0

    init(taxaAmostragem: Double) {
        self.taxaAmostragem = taxaAmostragem
        let corte: Double = 2000
        let rc = 1.0 / (2.0 * Double.pi * corte)
        let dt = 1.0 / taxaAmostragem
        self.alfaHP = Float(rc / (rc + dt))
        self.acumulador.reserveCapacity(tamanhoHop * 4)
    }

    /// Nível médio entre `inicio` e `fim` janelas atrás.
    private func mediaAnterior(_ inicio: Int, _ fim: Int) -> Float {
        var soma: Float = 0
        var n = 0
        for k in inicio...fim {
            soma += historico[((hIndice - k) % historico.count + historico.count) % historico.count]
            n += 1
        }
        return soma / Float(n)
    }

    /// Recebe um bloco de áudio mono e o processa em janelas de tamanho fixo.
    func processar(_ amostras: UnsafePointer<Float>, quantidade: Int) {
        acumulador.append(contentsOf: UnsafeBufferPointer(start: amostras, count: quantidade))
        while acumulador.count >= tamanhoHop {
            let janela = Array(acumulador[0..<tamanhoHop])
            acumulador.removeFirst(tamanhoHop)
            processarJanela(janela)
        }
    }

    private func processarJanela(_ janela: [Float]) {
        var somaTotal: Float = 0
        var somaAgudos: Float = 0
        for amostra in janela {
            // Passa-altas de 1ª ordem: y[n] = a * (y[n-1] + x[n] - x[n-1])
            let agudo = alfaHP * (saidaAnterior + amostra - entradaAnterior)
            saidaAnterior = agudo
            entradaAnterior = amostra
            somaTotal += amostra * amostra
            somaAgudos += agudo * agudo
        }
        let n = Float(janela.count)
        let rms = sqrt(somaTotal / n)
        let rmsAgudos = sqrt(somaAgudos / n)
        let db = 20 * log10(rms + 1e-9)
        let razaoAgudos = rmsAgudos / (rms + 1e-9)

        relogio += Double(tamanhoHop) / taxaAmostragem

        // Piso de ruído: sobe devagar, desce rápido. Fica colado no silêncio
        // do ambiente e não é arrastado para cima por um estalo.
        if db > pisoRuido {
            pisoRuido += (db - pisoRuido) * 0.01
        } else {
            pisoRuido += (db - pisoRuido) * 0.15
        }
        pisoRuido = max(pisoRuido, -75)

        contadorAmostras += 1
        if contadorAmostras % 8 == 0 {
            aoAmostrar?(db, pisoRuido, razaoAgudos)
        }

        guard relogio > silencioAte else {
            historico[hIndice] = db
            hIndice = (hIndice + 1) % historico.count
            return
        }

        switch estado {
        case .ocioso:
            let saltou = db > pisoRuido + ajustes.saltoOnsetDb
            let alto = db > ajustes.limiarPicoDb
            let estalado = razaoAgudos > ajustes.razaoAgudosMin
            let livre = (relogio - ultimaPalma) * 1000 > ajustes.refratarioMs
            if saltou && alto && estalado && livre {
                // Janela de ~40 ms a ~160 ms antes do ataque.
                preAoOnset = mediaAnterior(8, 30)
                estado = .verificando(inicio: relogio, pico: db)
            }

        case .verificando(let inicio, let pico):
            let picoAtualizado = max(pico, db)
            if (relogio - inicio) * 1000 >= ajustes.msParaDecair {
                // Passou o tempo de observação: só é palma se já tiver caído
                // e se tiver vindo do silêncio, não do meio de uma fala.
                // Só a palma que ABRE a sequência precisa provar que veio do
                // silêncio: as seguintes vêm logo depois de outra palma — e é
                // por isso que a fala não consegue iniciar uma sequência.
                let decaiu = picoAtualizado - db >= ajustes.decaimentoDb
                let abreSequencia = palmas.isEmpty
                let vinhaDoSilencio = !abreSequencia
                    || picoAtualizado - preAoOnset >= ajustes.preSilencioDb
                if decaiu && vinhaDoSilencio {
                    confirmarPalma(em: inicio, pico: picoAtualizado)
                }
                estado = .ocioso
            } else {
                estado = .verificando(inicio: inicio, pico: picoAtualizado)
            }
        }

        // A janela do gesto fechou sem palma nova: dispara o que se acumulou.
        // Nunca fecha com uma palma em verificação: ela ainda não entrou na
        // sequência, e fechar aqui quebraria gestos de palmas mais espaçadas.
        if case .ocioso = estado,
           let ultima = palmas.last,
           (relogio - ultima) * 1000 > ajustes.janelaMaxMs {
            dispararSequencia()
        }

        historico[hIndice] = db
        hIndice = (hIndice + 1) % historico.count
    }

    private func confirmarPalma(em instante: Double, pico: Float) {
        // Medido a partir do ataque, não da confirmação: a confirmação chega
        // msParaDecair depois, e contar dali dobraria a zona morta entre palmas.
        ultimaPalma = instante

        // Palma isolada demais para pertencer à sequência anterior: recomeça.
        if let ultima = palmas.last, (instante - ultima) * 1000 > ajustes.janelaMaxMs {
            palmas.removeAll()
        }
        palmas.append(instante)
        aoDetectarPalma?(palmas.count, pico)

        if palmas.count >= maxPalmas {
            dispararSequencia()
        }
    }

    private func dispararSequencia() {
        let quantidade = palmas.count
        palmas.removeAll()
        guard quantidade >= 2 else { return }   // uma palma sozinha nunca dispara
        estado = .ocioso
        silencioAte = relogio + ajustes.esperaPosGestoMs / 1000
        aoDetectarGesto?(quantidade)
    }
}
