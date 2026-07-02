import Foundation

func stdoutLine(_ value: String = "") {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
}

func stderrLine(_ value: String = "") {
    FileHandle.standardError.write(Data((value + "\n").utf8))
}

func formatRPM(_ value: Double?) -> String {
    guard let value else { return "unavailable" }
    return "\(Int(value.rounded())) RPM"
}

func formatCelsius(_ value: Double?) -> String {
    guard let value else { return "unavailable" }
    return String(format: "%.1f C", value)
}

func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value)
}
