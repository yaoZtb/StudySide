import AppKit

@main struct WindowArrangementTests {
    static func main() throws {
        for visible in [
            CGRect(x:0,y:40,width:1512,height:900),
            CGRect(x:-1920,y:0,width:1920,height:1080),
            CGRect(x:0,y:982,width:1440,height:900),
            CGRect(x:1512,y:-300,width:2560,height:1400)
        ] {
            let result = try WindowArrangement.frames(in: visible)
            precondition(!result.assistant.intersects(result.course))
            precondition(visible.contains(result.assistant) && visible.contains(result.course))
            precondition(result.assistant.minX > result.course.maxX)
            precondition(result.assistant.width >= 390 && result.assistant.height >= 620)
            let ax = WindowArrangement.axFrame(from: result.course, primaryTop: 982)
            let restored = WindowArrangement.appKitFrame(from: ax, primaryTop: 982)
            precondition(restored == result.course)
        }
        for small in [CGRect(x:0,y:0,width:800,height:900), CGRect(x:0,y:0,width:1440,height:600)] {
            do { _ = try WindowArrangement.frames(in: small); fatalError("Too-small screen accepted") } catch {}
        }
        if case .windowAccess(.cannotComplete) = WindowArrangement.windowAccessFailure(.cannotComplete, isTrusted: true) {} else {
            fatalError("A course app failure must not be reported as missing permission")
        }
        if case .permissionRequired = WindowArrangement.windowAccessFailure(.apiDisabled, isTrusted: false) {} else {
            fatalError("An unauthorized process must offer permission recovery")
        }
        precondition(WindowArrangement.Failure.permissionRequired.localizedDescription.contains("turn it off and on"))
        print("PASS: side-by-side geometry, no overlap, visible bounds, multiple monitor coordinates, insufficient space")
    }
}
