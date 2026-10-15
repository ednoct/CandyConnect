import 'package:url_launcher/url_launcher.dart';

class UrlLauncherUtils {
  static Future<void> launchTelegramSupport() async {
    final Uri appUri = Uri.parse('tg://resolve?domain=CandyConnectbot');
    final Uri webUri = Uri.parse('https://t.me/CandyConnectbot');

    try {
      bool launched = await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }
}
