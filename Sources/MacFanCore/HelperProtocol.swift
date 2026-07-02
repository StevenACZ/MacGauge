import Foundation

@objc(MacFanHelperXPCProtocol)
public protocol MacFanHelperXPCProtocol {
    func runCommand(_ commandData: Data, withReply reply: @escaping (Data) -> Void)
}
