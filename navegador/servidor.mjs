// Servidor local do Jarvis.
//
// Enquanto o Swift não compila, o "ouvido" roda no navegador (que já tem
// acesso ao microfone) e avisa aqui quando reconhece um gesto. Este processo
// é quem executa as ações no Mac. Lê o MESMO config/acoes.json da versão
// nativa, então o que você configurar aqui continua valendo depois.

import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const PORTA = Number(process.env.PORT ?? 4321);
const SIMULAR = process.env.JARVIS_SIMULAR === '1';

function caminhoConfig() {
  const candidatos = [
    process.env.JARVIS_CONFIG,
    join(homedir(), '.config', 'jarvis', 'acoes.json'),
    resolve(AQUI, '..', 'config', 'acoes.json'),
  ].filter(Boolean);
  const achado = candidatos.find((c) => existsSync(c));
  if (!achado) {
    console.error('erro: não encontrei acoes.json. Procurei em:\n  ' + candidatos.join('\n  '));
    process.exit(1);
  }
  return achado;
}

const CONFIG = caminhoConfig();

// Relê a cada gesto: dá para editar o JSON sem reiniciar o servidor.
async function lerConfig() {
  return JSON.parse(await readFile(CONFIG, 'utf8'));
}

function rodar(executavel, argumentos) {
  if (SIMULAR) {
    console.log(`   [simulação] ${executavel} ${argumentos.join(' ')}`);
    return;
  }
  execFile(executavel, argumentos, (erro, _saida, saidaErro) => {
    if (erro) console.error(`   falhou: ${executavel} — ${(saidaErro || erro.message).trim()}`);
  });
}

function executarAcao(acao, config) {
  const alvo = acao.alvo ?? '';
  switch (acao.tipo) {
    case 'abrir_app':    return rodar('/usr/bin/open', ['-a', alvo]);
    case 'ativar_app':   return rodar('/usr/bin/osascript', ['-e', `tell application "${alvo}" to activate`]);
    case 'abrir_url':    return rodar('/usr/bin/open', [alvo]);
    case 'abrir_arquivo':return rodar('/usr/bin/open', [alvo.replace(/^~/, homedir())]);
    case 'atalho':       return rodar('/usr/bin/shortcuts', ['run', alvo]);
    case 'applescript':  return rodar('/usr/bin/osascript', ['-e', alvo]);
    case 'shell':        return rodar('/bin/sh', ['-c', alvo]);
    case 'falar':        return rodar('/usr/bin/say', ['-v', config.voz ?? 'Luciana', alvo]);
    case 'tecla':        return rodar('/usr/bin/osascript', ['-e', `tell application "System Events" to ${alvo}`]);
    case 'som': {
      const caminho = alvo.startsWith('/') ? alvo : `/System/Library/Sounds/${alvo}.aiff`;
      return rodar('/usr/bin/afplay', [caminho]);
    }
    default: console.error(`   ação desconhecida: ${acao.tipo}`);
  }
}

async function dispararGesto(palmas) {
  const config = await lerConfig();
  const gesto = config.gestos?.[String(palmas)];
  const hora = new Date().toLocaleTimeString('pt-BR');
  if (!gesto) {
    console.log(`[${hora}] ${palmas} palmas — nenhum gesto configurado`);
    return { ok: false, mensagem: `nenhum gesto para ${palmas} palmas` };
  }
  console.log(`[${hora}] ${palmas} palmas → ${gesto.descricao ?? 'executando'}`);
  if (config.confirmacao) executarAcao(config.confirmacao, config);
  for (const acao of gesto.acoes ?? []) executarAcao(acao, config);
  return { ok: true, descricao: gesto.descricao ?? null };
}

// Faixas aceitas para cada ajuste. Serve de validação e também alimenta os
// sliders da página, para os dois lados nunca discordarem.
const LIMITES = {
  limiarPicoDb:     { min: -60, max: -5,   passo: 1,    unidade: 'dB' },
  saltoOnsetDb:     { min: 4,   max: 40,   passo: 1,    unidade: 'dB' },
  razaoAgudosMin:   { min: 0,   max: 1,    passo: 0.01, unidade: '' },
  decaimentoDb:     { min: 2,   max: 30,   passo: 1,    unidade: 'dB' },
  janelaMinMs:      { min: 40,  max: 400,  passo: 10,   unidade: 'ms' },
  janelaMaxMs:      { min: 200, max: 1500, passo: 25,   unidade: 'ms' },
  esperaPosGestoMs: { min: 200, max: 5000, passo: 100,  unidade: 'ms' },
};

function sanearAjustes(recebidos) {
  const limpos = {};
  for (const [chave, valor] of Object.entries(recebidos ?? {})) {
    const limite = LIMITES[chave];
    if (!limite) continue;                       // ignora chave desconhecida
    const n = Number(valor);
    if (!Number.isFinite(n)) continue;
    limpos[chave] = Math.min(limite.max, Math.max(limite.min, n));
  }
  return limpos;
}

// Lê o estado do Spotify sem abri-lo: sem a guarda de "is running", o
// AppleScript lançaria o app a cada consulta.
const SCRIPT_SPOTIFY = `if application "Spotify" is running then
	tell application "Spotify"
		try
			return (player state as string) & "|" & (name of current track) & "|" & (artist of current track)
		on error
			return (player state as string) & "||"
		end try
	end tell
else
	return "fechado"
end if`;

function estadoSpotify() {
  return new Promise((resolver) => {
    execFile('/usr/bin/osascript', ['-e', SCRIPT_SPOTIFY], { timeout: 4000 }, (erro, saida) => {
      if (erro) return resolver({ aberto: false });
      const texto = String(saida).trim();
      if (texto === 'fechado') return resolver({ aberto: false });
      const [estado, faixa, artista] = texto.split('|');
      resolver({ aberto: true, tocando: estado === 'playing', faixa: faixa || null, artista: artista || null });
    });
  });
}

function lerCorpo(req) {
  return new Promise((resolver, rejeitar) => {
    let dados = '';
    req.on('data', (parte) => {
      dados += parte;
      if (dados.length > 4096) rejeitar(new Error('corpo grande demais'));
    });
    req.on('end', () => resolver(dados));
    req.on('error', rejeitar);
  });
}

const servidor = createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
      const html = await readFile(join(AQUI, 'ouvinte.html'));
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      return res.end(html);
    }

    if (req.method === 'GET' && req.url === '/config') {
      const config = await lerConfig();
      const resumo = Object.fromEntries(
        Object.entries(config.gestos ?? {}).map(([k, g]) => [k, g.descricao ?? '(sem descrição)'])
      );
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      return res.end(JSON.stringify({ gestos: resumo, ajustes: config.ajustes ?? {}, limites: LIMITES }));
    }

    if (req.method === 'POST' && req.url === '/gesto') {
      const corpo = JSON.parse((await lerCorpo(req)) || '{}');
      const palmas = Number(corpo.palmas);
      if (!Number.isInteger(palmas) || palmas < 2 || palmas > 9) {
        res.writeHead(400, { 'content-type': 'application/json' });
        return res.end(JSON.stringify({ ok: false, mensagem: 'palmas inválido' }));
      }
      const resultado = await dispararGesto(palmas);
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      return res.end(JSON.stringify(resultado));
    }

    if (req.method === 'GET' && req.url === '/spotify') {
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      return res.end(JSON.stringify(await estadoSpotify()));
    }

    if (req.method === 'POST' && req.url === '/ajustes') {
      const recebidos = JSON.parse((await lerCorpo(req)) || '{}');
      const limpos = sanearAjustes(recebidos);
      const config = await lerConfig();
      config.ajustes = { ...(config.ajustes ?? {}), ...limpos };
      await writeFile(CONFIG, JSON.stringify(config, null, 2) + '\n', 'utf8');
      console.log(`[${new Date().toLocaleTimeString('pt-BR')}] ajustes salvos: ` +
        Object.entries(limpos).map(([k, v]) => `${k}=${v}`).join(' '));
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      return res.end(JSON.stringify({ ok: true, ajustes: config.ajustes }));
    }

    res.writeHead(404).end('não encontrado');
  } catch (erro) {
    console.error('erro na requisição:', erro.message);
    res.writeHead(500, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: false, mensagem: erro.message }));
  }
});

// Só 127.0.0.1: este servidor executa comandos, não pode ficar exposto na rede.
servidor.listen(PORTA, '127.0.0.1', () => {
  console.log('Jarvis — ouvido no navegador');
  console.log(`  config: ${CONFIG}`);
  if (SIMULAR) console.log('  modo simulação: nada será executado de verdade');
  console.log(`  abra: http://127.0.0.1:${PORTA}`);
});
