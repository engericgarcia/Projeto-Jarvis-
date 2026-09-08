import Foundation

/// Traduz as ações do JSON em comandos do macOS.
enum Executor {

    static func executar(gesto: Gesto, config: Config) {
        if let confirmacao = config.confirmacao {
            executar(acao: confirmacao, config: config)
        }
        for acao in gesto.acoes {
            executar(acao: acao, config: config)
        }
    }

    static func executar(acao: Acao, config: Config) {
        switch acao.tipo {
        case "abrir_app":
            rodar("/usr/bin/open", ["-a", acao.alvo])
        case "ativar_app":
            // Abre e traz para frente, mesmo que já esteja rodando.
            rodar("/usr/bin/osascript", ["-e", "tell application \"\(acao.alvo)\" to activate"])
        case "abrir_url":
            rodar("/usr/bin/open", [acao.alvo])
        case "abrir_arquivo":
            rodar("/usr/bin/open", [NSString(string: acao.alvo).expandingTildeInPath])
        case "atalho":
            rodar("/usr/bin/shortcuts", ["run", acao.alvo])
        case "applescript":
            rodar("/usr/bin/osascript", ["-e", acao.alvo])
        case "shell":
            rodar("/bin/sh", ["-c", acao.alvo])
        case "falar":
            rodar("/usr/bin/say", ["-v", config.voz ?? "Luciana", acao.alvo])
        case "som":
            let caminho = acao.alvo.hasPrefix("/")
                ? acao.alvo
                : "/System/Library/Sounds/\(acao.alvo).aiff"
            rodar("/usr/bin/afplay", [caminho])
        case "tecla":
            // Ex.: "key code 49" ou "keystroke \"c\" using command down".
            rodar("/usr/bin/osascript", ["-e", "tell application \"System Events\" to \(acao.alvo)"])
        default:
            log("ação desconhecida: \(acao.tipo)")
        }
    }

    private static func rodar(_ executavel: String, _ argumentos: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let processo = Process()
            processo.executableURL = URL(fileURLWithPath: executavel)
            processo.arguments = argumentos
            let erro = Pipe()
            processo.standardError = erro
            processo.standardOutput = Pipe()
            do {
                try processo.run()
                processo.waitUntilExit()
                if processo.terminationStatus != 0 {
                    let saida = String(
                        data: erro.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    log("falhou (\(processo.terminationStatus)): \(executavel) \(argumentos.joined(separator: " ")) \(saida)")
                }
            } catch {
                log("não consegui executar \(executavel): \(error.localizedDescription)")
            }
        }
    }

    static func log(_ mensagem: String) {
        let formatador = DateFormatter()
        formatador.dateFormat = "HH:mm:ss"
        let linha = "[\(formatador.string(from: Date()))] \(mensagem)\n"
        FileHandle.standardError.write(linha.data(using: .utf8)!)
    }
}
