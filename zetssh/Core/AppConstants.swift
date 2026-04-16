import Foundation

public struct AppConstants {
    public static let appName = "ZetSSH"
    public static let defaultSSHPort = 22
    public static let defaultTheme = "Dark"
    
    public struct Keepalive {
        public static let intervalSeconds: Int64 = 30
        // Total timeout = intervalSeconds × maxMissed = 30 × 10 = 300s (5 min)
        public static let maxMissed = 10
    }
    
    public struct Errors {
        public static let defaultErrorMessage = "Ocorreu um erro inesperado."
        public static let keychainReadError = "Não foi possível recuperar a senha de forma segura."
        public static let connectionFailed = "Falha ao estabelecer conexão SSH."
    }
}
