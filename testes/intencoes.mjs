// Testes do casamento de intenção. Rode com:  node testes/intencoes.mjs
//
// Usa os comandos reais do config/acoes.json, então também serve de guarda
// contra conflitos: se você acrescentar um comando cujas frases roubem o
// lugar de outro, um destes casos passa a falhar.

import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { casar, normalizar, pontuar } from '../navegador/intencoes.mjs';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const config = JSON.parse(await readFile(resolve(RAIZ, 'config/acoes.json'), 'utf8'));
const COMANDOS = config.comandos ?? [];

let total = 0, falhas = 0;
const linhas = [];

function conferir(dito, esperado) {
  total++;
  const achado = casar(dito, COMANDOS);
  const obtido = achado ? achado.comando.descricao : null;
  const ok = obtido === esperado;
  if (!ok) falhas++;
  const nota = achado ? achado.pontuacao.toFixed(2) : '—';
  linhas.push(`${ok ? '✓' : '✗'} "${dito}"`.padEnd(46) +
    `${(obtido ?? '(nada)').padEnd(32)} ${nota}` +
    (ok ? '' : `   ESPERADO: ${esperado ?? '(nada)'}`));
}

function grupo(nome) { linhas.push(`\n── ${nome}`); }

grupo('Frase exata de cada comando');
for (const c of COMANDOS) conferir(c.frases[0], c.descricao);

grupo('Variações naturais de fala');
conferir('Jarvis, pausa',                  'Pausar');
conferir('jarvis pula essa',               'Próxima faixa');
conferir('por favor abaixa o volume',      'Abaixar o volume');
conferir('aumenta o volume por favor',     'Aumentar o volume');
conferir('toca highway to hell',           'Highway to Hell');
conferir('que horas são?',                 'Dizer as horas');
conferir('abre o VS Code',                 'Abrir o VS Code');
conferir('abre o whatsapp pra mim',        'Abrir o WhatsApp');
conferir('hora de trabalhar',              'Modo trabalho');
conferir('tira o som',                     'Mudo / com som');

grupo('Acentos e maiúsculas não atrapalham');
conferir('PRÓXIMA FAIXA',                  'Próxima faixa');
conferir('silencio',                       'Pausar');
conferir('abre o codigo',                  'Abrir o VS Code');

grupo('Comando específico ganha do genérico');
// "toca" sozinho continua tocando, mas "toca highway to hell" não pode cair nele.
conferir('toca',                           'Continuar tocando');
conferir('toca ac dc',                     'Highway to Hell');

grupo('Não inventa comando para o que não é comando');
conferir('bom dia tudo bem com você',      null);
conferir('preciso comprar pão amanhã',     null);
conferir('',                               null);
conferir('asdfghjkl',                      null);

// Duas checagens diretas das funções auxiliares.
grupo('Funções auxiliares');
total++;
if (normalizar('Pausa, Jarvis!') !== 'pausa jarvis') { falhas++; linhas.push('✗ normalizar remove pontuação e acento'); }
else linhas.push('✓ normalizar remove pontuação e acento');
total++;
if (pontuar('pausa', 'pausa') !== 1) { falhas++; linhas.push('✗ frase idêntica pontua 1'); }
else linhas.push('✓ frase idêntica pontua 1');

console.log(linhas.join('\n'));
console.log('');
console.log(falhas ? `${falhas} de ${total} casos falharam` : `${total} casos, todos passaram`);
process.exit(falhas ? 1 : 0);
