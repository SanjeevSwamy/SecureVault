import 'dart:convert';
import 'dart:io';
import 'desktop_wallet_service.dart';

class DesktopWalletConnector {
  static HttpServer? _server;

  static Future<void> startListener() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 5050);
      print('🧠 Listening on localhost:5050 for wallet connection...');
      _server!.listen(_handleRequest);
    } catch (e) {
      print('❌ Error starting server: $e');
    }
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    if (request.method == 'POST' &&
        request.uri.path == '/wallet-connect') {
      final body = await utf8.decoder.bind(request).join();
      final data = json.decode(body);

      final address = data['address'];
      final token = data['token'];

      if (address != null && token != null) {
        print('📨 Received wallet: $address');

        await DesktopWalletService.saveWalletConnection(address, token);
        DesktopWalletService.triggerWalletConnected(address);

        request.response.statusCode = 200;
        request.response.write('success');
      } else {
        request.response.statusCode = 400;
        request.response.write('Missing required fields');
      }
    } else {
      request.response.statusCode = 404;
      request.response.write('Not Found');
    }

    await request.response.close();
  }

  static void stop() {
    _server?.close(force: true);
    print('🛑 Stopped localhost listener');
  }
}
