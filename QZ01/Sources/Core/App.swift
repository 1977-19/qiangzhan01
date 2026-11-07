import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: windowScene)
        w.backgroundColor = .black
        w.rootViewController = RootViewController()
        w.makeKeyAndVisible()
        window = w
    }
}

/// Holds the menu / game screens and keeps the device in landscape with no status bar.
final class RootViewController: UIViewController {
    private var current: UIViewController?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var childForStatusBarHidden: UIViewController? { current }
    override var childForHomeIndicatorAutoHidden: UIViewController? { current }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { current }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        showMenu()
    }

    func show(_ vc: UIViewController) {
        if let old = current {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        addChild(vc)
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
        current = vc
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    func showMenu() {
        let menu = MenuViewController()
        menu.onStart = { [weak self] settings in
            self?.startGame(settings)
        }
        show(menu)
    }

    func startGame(_ settings: GameSettings) {
        let game = GameViewController(settings: settings)
        game.onExit = { [weak self] in
            self?.showMenu()
        }
        show(game)
    }
}
