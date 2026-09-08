import AVFoundation
import Foundation

// ---------------------------------------------------------------- argumentos
let argumentos = Array(CommandLine.arguments.dropFirst())
let modoDebug = argumentos.contains("--debug")

func valorDe(_ chave: String) -> String? {
    guard let i = argumentos.firstIndex(of: chave), i + 1 < argumentos.count else { return nil }
    return argumentos[i + 1]
}

if argumentos.contains("--ajuda") || argumentos.contains("-h") {
    print("""
    jarvis-ouvido — detecta palmas e dispara ações no Mac

      --debug            mostra níveis de áudio ao vivo e cada palma detectada
      --config <arquivo> usa outro JSON de ações
      --testar <n>       executa o gesto de n palmas e sai (sem microfone)
      --listar           mostra os gestos configurados e sai
    """)
    exit(0)
}

// ------------------------------------------------------------------- config
guard let caminhoConfig = CarregadorConfig.resolverCaminho(argumento: valorDe("--config")) else {
    Executor.log("erro: nenhum arquivo de configuração encontrado.")
    Executor.log("procurei em: --config, $JARVIS_CONFIG, ~/.config/jarvis/acoes.json e no padrão do build.")
    exit(1)
}
guard let carregador = CarregadorConfig(caminho: caminhoConfig) else { exit(1) }
Executor.log("configuração: \(caminhoConfig.path)")

if argumentos.contains("--listar") {
    let config = carregador.atual
    for chave in config.gestos.keys.sorted() {
        let gesto = config.gestos[chave]!
        print("\(chave) palmas → \(gesto.descricao ?? "(sem descrição)")")
        for acao in gesto.acoes { print("    \(acao.tipo): \(acao.alvo)") }
    }
    exit(0)
}

if let n = valorDe("--testar") {
    let config = carregador.atual
    guard let gesto = config.gestos[n] else {
        Executor.log("erro: não há gesto configurado para \(n) palmas.")
        exit(1)
    }
    Executor.log("testando gesto de \(n) palmas → \(gesto.descricao ?? "")")
    Executor.executar(gesto: gesto, config: config)
    Thread.sleep(forTimeInterval: 3)   // dá tempo dos processos filhos rodarem
    exit(0)
}

// ------------------------------------------------------- permissão de microfone
let semaforo = DispatchSemaphore(value: 0)
var microfoneLiberado = false
switch AVCaptureDevice.authorizationStatus(for: .audio) {
case .authorized:
    microfoneLiberado = true
    semaforo.signal()
case .notDetermined:
    AVCaptureDevice.requestAccess(for: .audio) { permitido in
        microfoneLiberado = permitido
        semaforo.signal()
    }
default:
    semaforo.signal()
}
semaforo.wait()

guard microfoneLiberado else {
    Executor.log("erro: acesso ao microfone negado.")
    Executor.log("libere em Ajustes do Sistema → Privacidade e Segurança → Microfone.")
    exit(1)
}

// ---------------------------------------------------------------- áudio
let motor = AVAudioEngine()
let entrada = motor.inputNode
let formato = entrada.outputFormat(forBus: 0)

guard formato.sampleRate > 0 else {
    Executor.log("erro: nenhum dispositivo de entrada disponível.")
    exit(1)
}

let detector = DetectorPalmas(taxaAmostragem: formato.sampleRate)
detector.maxPalmas = carregador.atual.maxPalmas
if let a = carregador.atual.ajustes {
    if let v = a.limiarPicoDb      { detector.ajustes.limiarPicoDb = v }
    if let v = a.saltoOnsetDb      { detector.ajustes.saltoOnsetDb = v }
    if let v = a.razaoAgudosMin    { detector.ajustes.razaoAgudosMin = v }
    if let v = a.decaimentoDb      { detector.ajustes.decaimentoDb = v }
    if let v = a.janelaMinMs       { detector.ajustes.janelaMinMs = v }
    if let v = a.janelaMaxMs       { detector.ajustes.janelaMaxMs = v }
    if let v = a.esperaPosGestoMs  { detector.ajustes.esperaPosGestoMs = v }
}

detector.aoDetectarGesto = { quantidade in
    let config = carregador.atual
    guard let gesto = config.gestos[String(quantidade)] else {
        Executor.log("\(quantidade) palmas — nenhum gesto configurado")
        return
    }
    Executor.log("\(quantidade) palmas → \(gesto.descricao ?? "executando")")
    Executor.executar(gesto: gesto, config: config)
}

if modoDebug {
    detector.aoDetectarPalma = { indice, pico in
        FileHandle.standardError.write("\n  palma #\(indice)  pico \(String(format: "%.1f", pico)) dB\n".data(using: .utf8)!)
    }
    var ultimaImpressao = Date.distantPast
    detector.aoAmostrar = { db, piso, agudos in
        guard Date().timeIntervalSince(ultimaImpressao) > 0.15 else { return }
        ultimaImpressao = Date()
        let barra = String(repeating: "▮", count: max(0, min(30, Int((db + 70) / 2.4))))
        let linha = String(
            format: "\r  nível %6.1f dB  piso %6.1f dB  agudos %4.2f  %-30s",
            db, piso, agudos, (barra as NSString).utf8String!
        )
        FileHandle.standardError.write(linha.data(using: .utf8)!)
    }
}

// Buffer reaproveitado para somar os canais quando a entrada é estéreo.
var mono = [Float](repeating: 0, count: 8192)

entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
    guard let canais = buffer.floatChannelData else { return }
    let quadros = Int(buffer.frameLength)
    let numCanais = Int(buffer.format.channelCount)
    guard quadros > 0 else { return }

    if numCanais == 1 {
        detector.processar(canais[0], quantidade: quadros)
    } else {
        if mono.count < quadros { mono = [Float](repeating: 0, count: quadros) }
        for i in 0..<quadros {
            var soma: Float = 0
            for c in 0..<numCanais { soma += canais[c][i] }
            mono[i] = soma / Float(numCanais)
        }
        mono.withUnsafeBufferPointer { ponteiro in
            detector.processar(ponteiro.baseAddress!, quantidade: quadros)
        }
    }
}

// Trocar de microfone (fone bluetooth, dock) derruba o tap: religa o motor.
NotificationCenter.default.addObserver(
    forName: .AVAudioEngineConfigurationChange,
    object: motor,
    queue: .main
) { _ in
    Executor.log("dispositivo de áudio mudou — reiniciando a escuta")
    if !motor.isRunning { try? motor.start() }
}

do {
    try motor.start()
} catch {
    Executor.log("erro ao iniciar o áudio: \(error.localizedDescription)")
    exit(1)
}

let gestosAtivos = carregador.atual.gestos.keys.sorted().joined(separator: ", ")
Executor.log("ouvindo em \(Int(formato.sampleRate)) Hz — gestos ativos: \(gestosAtivos) palmas")
if modoDebug { Executor.log("modo debug: bata palmas e observe os níveis") }

RunLoop.main.run()
