import Foundation

@objc(M4FanHelperXPCProtocol)
public protocol M4FanHelperXPCProtocol {
    func runCommand(_ commandData: Data, withReply reply: @escaping (Data) -> Void)
}
