# Jarvis

Assistente para Mac acionado por **palmas**. Duas palmas abrem uma coisa,
três palmas abrem outra — você define no `config/acoes.json`.

## Começar agora (sem instalar nada)

```bash
./iniciar.sh
```

Abre `http://127.0.0.1:4321`. Clique em **Ativar microfone**, permita o acesso
e bata palmas. Deixe a aba aberta — a detecção roda na thread de áudio e
continua funcionando com a aba em segundo plano.

O microfone fica no navegador; quem executa as ações no Mac é o servidor Node
local (só escuta em `127.0.0.1`).

Para ver o que aconteceria sem abrir nada de verdade:

```bash
JARVIS_SIMULAR=1 ./iniciar.sh
```

## Gestos atuais

| gesto | o que faz |
|---|---|
| 👏👏 | abre o Spotify e toca *Highway to Hell* |
| 👏👏👏 | play / pause |
| 👏👏👏👏 | próxima faixa |

Só o gesto mais longo dispara na hora. Os menores esperam a janela de
agrupamento fechar (600 ms) antes de disparar, para não serem confundidos com
o começo de um gesto maior. Por isso não vale a pena passar de quatro palmas:
cada nível a mais atrasa todos os outros.

## Configurar os gestos

Tudo vive em [`config/acoes.json`](config/acoes.json). Editou, salvou, valeu —
não precisa reiniciar nada.

```json
{
  "gestos": {
    "2": {
      "descricao": "Abrir Spotify",
      "acoes": [{ "tipo": "abrir_app", "alvo": "Spotify" }]
    }
  }
}
```

Para tocar uma música específica, use um AppleScript com a URI da faixa — o ID
sai da própria URL do Spotify (`open.spotify.com/track/<ID>`):

```applescript
tell application "Spotify" to play track "spotify:track:2zYzyRzz6pRmhPzyfMEC8s"
```

Tipos de ação disponíveis:

| tipo | o que faz | exemplo de `alvo` |
|---|---|---|
| `abrir_app` | abre um aplicativo | `"Spotify"` |
| `ativar_app` | abre e traz para frente | `"WhatsApp"` |
| `abrir_url` | abre um link no navegador padrão | `"https://gmail.com"` |
| `abrir_arquivo` | abre arquivo ou pasta | `"~/Projetos"` |
| `atalho` | roda um Atalho do app Atalhos | `"Modo Foco"` |
| `applescript` | executa AppleScript | `"set volume output volume 30"` |
| `tecla` | manda uma tecla pro sistema | `"keystroke \"h\" using command down"` |
| `falar` | fala em voz alta | `"Bom dia"` |
| `som` | toca um som do sistema | `"Tink"` |
| `shell` | roda um comando | `"pmset displaysleepnow"` |

Chaves extras: `voz` (voz do `say`, padrão `Luciana`) e `confirmacao`
(ação disparada antes de qualquer gesto — por padrão um bipe).

> `shell` e `applescript` executam o que estiver escrito no arquivo. Como o
> servidor só aceita conexões de `127.0.0.1`, isso fica restrito à sua máquina.

## Ajustar a sensibilidade

Em `ajustes`, dentro do mesmo JSON:

| campo | efeito |
|---|---|
| `limiarPicoDb` | nível mínimo da palma. Mais negativo = mais sensível |
| `saltoOnsetDb` | quanto a palma precisa saltar acima do ruído do ambiente |
| `razaoAgudosMin` | quanto de agudo o som precisa ter (separa palma de batida grave) |
| `decaimentoDb` | queda exigida depois do pico (separa palma de fala e música) |
| `janelaMaxMs` | intervalo máximo entre as palmas do mesmo gesto |
| `esperaPosGestoMs` | pausa após disparar, para não ouvir a própria confirmação |

Não precisa editar o arquivo à mão para isso: a página tem um slider para cada
um desses campos. O que você mexe vale na hora, sem reiniciar nada, e o botão
**Gravar no arquivo** persiste em `acoes.json`. O servidor valida cada valor
contra uma faixa aceita antes de gravar.

O anel central mostra o nível ao vivo, com o limiar marcado em laranja e o piso
de ruído em tracejado — dá para ver se a palma cruzou a linha. Se as palmas não
pegam, olhe o pico que aparece no registro e baixe o **limiar** até um pouco
abaixo dele. Se dispara sozinho, suba o **salto** ou os **agudos**.

## Versão nativa (em segundo plano, sem navegador)

Existe uma implementação em Swift em [`ouvido/`](ouvido/) — mesma lógica de
detecção, mesmo `acoes.json`, rodando como app de fundo sem aba aberta.

**Ela ainda não compila neste Mac.** As Command Line Tools estão com
instalações misturadas (2023 + 2024 + 2025): o SDK foi construído com
`swiftlang-6.0.3.1.5` e o compilador instalado é o `6.0.3.1.10`, então nem
`import Foundation` passa. Para consertar:

```bash
sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install
```

Depois disso:

```bash
bash ouvido/build.sh                      # gera build/Jarvis.app
./build/Jarvis.app/Contents/MacOS/jarvis-ouvido --debug   # calibrar
bash scripts/instalar-launchagent.sh      # subir sozinho no login
```

Opções: `--debug` (níveis ao vivo), `--listar`, `--testar 2`, `--config <arquivo>`.

O binário mora dentro de um `.app` de propósito: o macOS concede permissão de
microfone a aplicativos, não a executáveis soltos — assim o Jarvis aparece com
nome próprio em *Privacidade e Segurança → Microfone*.

## Como a detecção funciona

Uma palma tem três marcas que a separam de fala, música e porta batendo:

1. **ataque abrupto** — o nível salta ~14 dB acima do piso de ruído em poucos ms;
2. **decaimento curto** — cai 9 dB em ~130 ms (fala e música sustentam);
3. **energia em agudos** — é estalo de banda larga, não um "tum" grave.

Só conta como palma quando as três acontecem juntas. Palmas confirmadas são
agrupadas por proximidade no tempo: se o maior gesto configurado é o de 3
palmas, o de 2 espera a janela fechar antes de disparar; se o maior é o de 2,
dispara na segunda palma, sem espera.

As palmas do mesmo gesto podem estar entre 130 ms e 600 ms uma da outra —
ritmo de palma normal cabe folgado nessa faixa.

Verificado com áudio sintético, 15 cenários: dispara certo para 2, 3 e 4
palmas em ritmo rápido, lento e irregular, inclusive com ruído de fundo alto;
ignora palma isolada e palmas espaçadas demais; e não reage a fala alta,
batida grave na mesa, ruído contínuo, música com kick forte nem digitação.

## Estrutura

```
config/acoes.json      gestos e ações (fonte da verdade das duas versões)
navegador/servidor.mjs servidor local: executa ações, lê o Spotify, grava ajustes
navegador/ouvinte.html HUD e detector de palmas em AudioWorklet
ouvido/Sources/        versão nativa em Swift
scripts/               instalação do LaunchAgent
```

## Próximos passos

- Wake word "Jarvis" com reconhecimento de fala local do macOS (`SFSpeechRecognizer`)
- Cérebro híbrido: intenções simples resolvidas localmente, o resto via Claude
