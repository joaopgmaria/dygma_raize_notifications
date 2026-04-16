import Foundation

let dygma = "/Users/jmaria/playground/keyboard/bin/dygma"

func run(_ args: String...) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: dygma)
    p.arguments = Array(args)
    try? p.run()
}

DistributedNotificationCenter.default().addObserver(
    forName: .init("com.apple.screenIsLocked"),
    object: nil, queue: nil
) { _ in run("matrix", "all", "green", "--force") }

DistributedNotificationCenter.default().addObserver(
    forName: .init("com.apple.screenIsUnlocked"),
    object: nil, queue: nil
) { _ in run("clear") }

RunLoop.main.run()
