import Foundation

enum AppState {
    case launch
    case welcome
    case connecting
    case exerciseSelection
    case activeSession
}

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed
}