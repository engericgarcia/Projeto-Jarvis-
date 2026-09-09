import Foundation

/// Uma ação que o Jarvis executa quando reconhece um gesto.
struct Acao: Codable {
    let tipo: String
    let alvo: String
}

/// Um gesto configurado (ex.: "2" = duas palmas) e o que ele dispara.
struct Gesto: Codable {
    let descricao: String?
    let acoes: [Acao]
}

/// Parâmetros de sensibilidade do detector. Todos opcionais no JSON:
/// o que não vier usa o padrão de `DetectorPalmas.Ajustes`.
struct AjustesJSON: Codable {
    var limiarPicoDb: Float?
    var saltoOnsetDb: Float?
    var razaoAgudosMin: Float?
    var decaimentoDb: Float?
    var preSilencioDb: Float?
    var janelaMinMs: Double?
    var janelaMaxMs: Double?
    var esperaPosGestoMs: Double?
}

struct Config: Codable {
    /// Voz do macOS usada nas ações do tipo "falar" (veja `say -v '?'`).
    var voz: String?
    var confirmacao: Acao?
    var gestos: [String: Gesto]
    var ajustes: AjustesJSON?

    /// Maior número de palmas que existe na configuração. O detector usa isso
    /// para disparar na hora quando já não há gesto mais longo possível.
    var maxPalmas: Int {
        gestos.keys.compactMap(Int.init).max() ?? 2
    }
}

/// Carrega o JSON de configuração e recarrega sozinho quando o arquivo muda,
/// para você editar as ações sem recompilar nem reiniciar o Jarvis.
final class CarregadorConfig {
    let caminho: URL
    private var config: Config
    private var modificadoEm: Date?
    private let fila = DispatchQueue(label: "jarvis.config")

    init?(caminho: URL) {
        self.caminho = caminho
        guard let carregada = CarregadorConfig.ler(caminho) else { return nil }
        self.config = carregada
        self.modificadoEm = CarregadorConfig.dataDeModificacao(caminho)
    }

    /// Config atual, relendo o arquivo se ele mudou desde a última consulta.
    var atual: Config {
        fila.sync {
            let agora = CarregadorConfig.dataDeModificacao(caminho)
            if agora != modificadoEm, let nova = CarregadorConfig.ler(caminho) {
                config = nova
                modificadoEm = agora
                FileHandle.standardError.write("[jarvis] configuração recarregada\n".data(using: .utf8)!)
            }
            return config
        }
    }

    private static func ler(_ url: URL) -> Config? {
        guard let dados = try? Data(contentsOf: url) else {
            FileHandle.standardError.write("[jarvis] erro: não consegui ler \(url.path)\n".data(using: .utf8)!)
            return nil
        }
        do {
            return try JSONDecoder().decode(Config.self, from: dados)
        } catch {
            FileHandle.standardError.write("[jarvis] erro no JSON \(url.path): \(error)\n".data(using: .utf8)!)
            return nil
        }
    }

    private static func dataDeModificacao(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Ordem de busca: --config, $JARVIS_CONFIG, ~/.config/jarvis/acoes.json,
    /// e por último o caminho gravado no Info.plist na hora do build.
    static func resolverCaminho(argumento: String?) -> URL? {
        var candidatos: [String] = []
        if let argumento { candidatos.append(argumento) }
        if let env = ProcessInfo.processInfo.environment["JARVIS_CONFIG"] { candidatos.append(env) }
        candidatos.append(NSString(string: "~/.config/jarvis/acoes.json").expandingTildeInPath)
        if let padrao = Bundle.main.object(forInfoDictionaryKey: "JarvisConfigPadrao") as? String {
            candidatos.append(padrao)
        }
        return candidatos.first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}
