import Foundation

/// Narrow boundary between the app and the device-specific LED controller.
/// Implementations must report hardware state from reads; callers never infer
/// success from a write request alone.
protocol LEDHardwareControlling: Sendable {
    func readLEDEnabled() async throws -> Bool
    func setLEDEnabled(_ enabled: Bool) async throws
}
