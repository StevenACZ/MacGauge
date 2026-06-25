import Foundation

public enum HelperPaths {
    public static let label = "com.stevenacz.M4FanControl.XPCHelper"
    public static let launchDaemonPlistName = "\(label).plist"
    public static let bundleProgram = "Contents/MacOS/M4FanHelper"
    public static let machServiceName = label
}

public enum LegacyHelperPaths {
    public static let label = "com.stevenacz.M4FanControl.Helper"
    public static let toolPath = "/Library/PrivilegedHelperTools/\(label)"
    public static let plistPath = "/Library/LaunchDaemons/\(label).plist"
}
