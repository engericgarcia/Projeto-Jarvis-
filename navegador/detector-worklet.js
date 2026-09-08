// Detector de palmas — roda dentro de um AudioWorklet, ou seja, na thread de
// áudio: continua funcionando com a aba em segundo plano, ao contrário de
// timers e de requestAnimationFrame.
//
// Mesma lógica da versão Swift em ouvido/Sources/DetectorPalmas.swift. Uma
// palma tem três marcas que a separam de fala, música e batida de porta:
// ataque abrupto, decaimento curto e energia em agudos. As três juntas.
//
// Este arquivo é carregado por ouvinte.html (uso real) e por testes.html
// (áudio sintético), para os dois exercitarem exatamente o mesmo código.
class DetectorPalmas extends AudioWorkletProcessor {
  constructor(opcoes) {
    super();
    const o = opcoes.processorOptions || {};
    this.a = Object.assign({
      limiarPicoDb: -32, saltoOnsetDb: 14, razaoAgudosMin: 0.25, decaimentoDb: 9,
      msParaDecair: 130, refratarioMs: 130, janelaMinMs: 90, janelaMaxMs: 700,
      esperaPosGestoMs: 1800
    }, o.ajustes || {});
    this.maxPalmas = o.maxPalmas || 2;

    // A página pode reajustar a sensibilidade sem recriar o nó.
    this.port.onmessage = ({ data }) => {
      if (data && data.ajustes) Object.assign(this.a, data.ajustes);
      if (data && data.maxPalmas) this.maxPalmas = data.maxPalmas;
    };

    this.hop = 256;
    this.buffer = new Float32Array(this.hop);
    this.preenchido = 0;

    const corte = 2000, rc = 1 / (2 * Math.PI * corte), dt = 1 / sampleRate;
    this.alfaHP = rc / (rc + dt);
    this.entradaAnterior = 0; this.saidaAnterior = 0;

    this.relogio = 0;
    this.piso = -60;
    this.silencioAte = 0.6;
    this.estado = 'ocioso';
    this.inicioOnset = 0; this.pico = 0;
    this.ultimaPalma = -1;
    this.palmas = [];
    this.contador = 0;
  }

  process(entradas) {
    const canal = entradas[0] && entradas[0][0];
    if (!canal) return true;
    for (let i = 0; i < canal.length; i++) {
      this.buffer[this.preenchido++] = canal[i];
      if (this.preenchido === this.hop) { this.processarJanela(); this.preenchido = 0; }
    }
    return true;
  }

  processarJanela() {
    let somaTotal = 0, somaAgudos = 0;
    for (let i = 0; i < this.hop; i++) {
      const x = this.buffer[i];
      const agudo = this.alfaHP * (this.saidaAnterior + x - this.entradaAnterior);
      this.saidaAnterior = agudo; this.entradaAnterior = x;
      somaTotal += x * x; somaAgudos += agudo * agudo;
    }
    const rms = Math.sqrt(somaTotal / this.hop);
    const rmsAgudos = Math.sqrt(somaAgudos / this.hop);
    const db = 20 * Math.log10(rms + 1e-9);
    const razaoAgudos = rmsAgudos / (rms + 1e-9);

    this.relogio += this.hop / sampleRate;

    if (db > this.piso) this.piso += (db - this.piso) * 0.01;
    else this.piso += (db - this.piso) * 0.15;
    if (this.piso < -75) this.piso = -75;

    if (++this.contador % 6 === 0) {
      this.port.postMessage({ tipo: 'nivel', db, piso: this.piso, agudos: razaoAgudos });
    }
    if (this.relogio <= this.silencioAte) return;

    const a = this.a;
    if (this.estado === 'ocioso') {
      const saltou = db > this.piso + a.saltoOnsetDb;
      const alto = db > a.limiarPicoDb;
      const estalado = razaoAgudos > a.razaoAgudosMin;
      const livre = (this.relogio - this.ultimaPalma) * 1000 > a.refratarioMs;
      if (saltou && alto && estalado && livre) {
        this.estado = 'verificando'; this.inicioOnset = this.relogio; this.pico = db;
      }
    } else {
      if (db > this.pico) this.pico = db;
      if ((this.relogio - this.inicioOnset) * 1000 >= a.msParaDecair) {
        if (this.pico - db >= a.decaimentoDb) this.confirmarPalma(this.inicioOnset, this.pico);
        this.estado = 'ocioso';
      }
    }

    // Nunca fecha a janela com uma palma em verificação: ela ainda não entrou
    // na sequência, e fechar aqui quebraria gestos de palmas mais espaçadas.
    if (this.estado === 'ocioso' && this.palmas.length &&
        (this.relogio - this.palmas[this.palmas.length - 1]) * 1000 > a.janelaMaxMs) {
      this.dispararSequencia();
    }
  }

  confirmarPalma(instante, pico) {
    // Medido a partir do ataque, não da confirmação: a confirmação chega
    // msParaDecair depois, e contar dali dobraria a zona morta entre palmas.
    this.ultimaPalma = instante;
    const ultima = this.palmas[this.palmas.length - 1];
    if (ultima !== undefined && (instante - ultima) * 1000 > this.a.janelaMaxMs) this.palmas = [];
    this.palmas.push(instante);
    this.port.postMessage({ tipo: 'palma', indice: this.palmas.length, pico });
    if (this.palmas.length >= this.maxPalmas) this.dispararSequencia();
  }

  dispararSequencia() {
    const quantidade = this.palmas.length;
    this.palmas = [];
    this.port.postMessage({ tipo: 'sequencia', n: 0 });
    if (quantidade < 2) return;
    this.estado = 'ocioso';
    this.silencioAte = this.relogio + this.a.esperaPosGestoMs / 1000;
    this.port.postMessage({ tipo: 'gesto', palmas: quantidade });
  }
}
registerProcessor('detector-palmas', DetectorPalmas);
