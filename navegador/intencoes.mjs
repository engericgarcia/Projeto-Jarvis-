// Casamento de intenção: transforma o que foi transcrito no comando mais
// provável. Sem modelo de linguagem — é comparação de texto normalizado, o
// que basta para um conjunto fechado de comandos e não custa nada nem depende
// de rede.

/// Tira acentos, pontuação e maiúsculas: "Pausa, Jarvis!" → "pausa jarvis".
export function normalizar(texto) {
  return String(texto ?? '')
    .toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')   // remove diacríticos
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Palavras que não ajudam a distinguir um comando de outro.
const VAZIAS = new Set(['jarvis', 'por', 'favor', 'o', 'a', 'os', 'as', 'e', 'de', 'da', 'do', 'um', 'uma']);

function palavrasUteis(texto) {
  return texto.split(' ').filter((p) => p && !VAZIAS.has(p));
}

/// Quanto uma frase de comando combina com o que foi dito, de 0 a 1.
export function pontuar(dito, frase) {
  if (!dito || !frase) return 0;
  if (dito === frase) return 1;

  // Frase inteira presente, respeitando limites de palavra.
  if (` ${dito} `.includes(` ${frase} `)) {
    // Quanto menos sobra em volta, mais provável ser esse o comando.
    const sobra = dito.length - frase.length;
    return Math.max(0.72, 0.95 - sobra * 0.01);
  }

  // Caso contrário, quanto das palavras do comando apareceram.
  const daFrase = palavrasUteis(frase);
  if (!daFrase.length) return 0;
  const ditas = new Set(palavrasUteis(dito));
  const comuns = daFrase.filter((p) => ditas.has(p)).length;
  return (comuns / daFrase.length) * 0.7;
}

/// Melhor comando para o que foi dito, ou null se nada chegou perto.
/// `comandos` é a lista do acoes.json: [{ descricao, frases, acoes }, ...]
export function casar(dito, comandos, minimo = 0.6) {
  const texto = normalizar(dito);
  let melhor = null;

  for (const comando of comandos ?? []) {
    for (const frase of comando.frases ?? []) {
      const pontuacao = pontuar(texto, normalizar(frase));
      if (!melhor || pontuacao > melhor.pontuacao) {
        melhor = { comando, frase, pontuacao };
      }
    }
  }

  if (!melhor || melhor.pontuacao < minimo) return null;
  return melhor;
}
