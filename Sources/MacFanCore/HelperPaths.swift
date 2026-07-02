import Foundation

public enum HelperPaths {
    public static let label = "com.stevenacz.MacFan.XPCHelper"
    public static let launchDaemonPlistName = "\(label).plist"
    public static let bundleProgram = "Contents/MacOS/MacFanHelper"
    public static let machServiceName = label
}

public enum LegacyHelperPaths {
    // Historical label from pre-XPC releases; must keep the old app name so
    // cleanup can find and remove installs made before the MacFan rename.
    public static let label = "com.stevenacz.M4FanControl.Helper"
    public static let toolPath = "/Library/PrivilegedHelperTools/\(label)"
    public static let plistPath = "/Library/LaunchDaemons/\(label).plist"
}
