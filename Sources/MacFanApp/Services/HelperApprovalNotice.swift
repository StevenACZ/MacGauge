enum HelperApprovalNotice {
    static func isVisible(state: HelperCommandService.HelperState, fanControlAvailable: Bool) -> Bool {
        state == .needsApproval && fanControlAvailable
    }

    static func showsBanner(state: HelperCommandService.HelperState, fanControlAvailable: Bool) -> Bool {
        state == .needsApproval
            ? isVisible(state: state, fanControlAvailable: fanControlAvailable)
            : state != .ready
    }
}
