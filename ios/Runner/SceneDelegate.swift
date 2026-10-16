import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    window?.backgroundColor = UIColor(
      red: 11.0 / 255.0,
      green: 15.0 / 255.0,
      blue: 25.0 / 255.0,
      alpha: 1.0
    )
  }
}