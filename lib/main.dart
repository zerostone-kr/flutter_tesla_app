import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

WebViewController? _controller;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tesla API Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String accessToken = '';
  HttpServer? _server;
  final int _port = 8080;  // 로컬 서버 포트

  final String clientId = '2110d263-ec90-42b5-9fd9-e1064d93a976';
  final String clientSecret = 'ta-secret.GUwR%lb%N7UnHTeb';
  final String redirectUri = 'http://localhost:8080/callback';  // 로컬 서버 리디렉션 URI
  // final String redirectUri = 'https://auth.tesla.com/void/callback';  // 로컬 서버 리디렉션 URI

  @override
  void initState() {
    super.initState();
    _startLocalServer();
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      print('[zerostone] Local server started on port: $_port');
      _server?.listen((HttpRequest request) {
        if (request.uri.path == '/callback') {
          final code = request.uri.queryParameters['code'];
          if (code != null) {
            _fetchAccessToken(code);
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..write('Authentication successful. You can close this tab.')
            ..close();
        }
      });
    } catch (e) {
      print('[zerostone] Failed to start local server: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('[zerostone] Build () start...');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tesla API Demo'),
      ),
      body: WebView(
        initialUrl: 'https://auth.tesla.com/oauth2/v3/authorize?response_type=code&client_id=$clientId&redirect_uri=$redirectUri&scope=oopenid%20offline_access%20user_data vehicle_device_data vehicle_cmds vehicle_charging_cmds',
        javascriptMode: JavascriptMode.unrestricted,
        onWebViewCreated: (WebViewController webViewController) {
          _controller = webViewController;
        },
      ),
    );
  }

  Future<void> _fetchAccessToken(String code) async {
    final response = await http.post(
      Uri.parse('https://auth.tesla.com/oauth2/v3/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      setState(() {
        accessToken = responseData['access_token'];
      });

      _getVehicleData();
    } else {
      print('Failed to fetch access token: ${response.statusCode}');
      print('Response body: ${response.body}');
    }
  }

  Future<void> _getVehicleData() async {
    final response = await http.get(
      Uri.parse('https://owner-api.teslamotors.com/api/1/vehicles'),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    final vehicleData = json.decode(response.body);
    print(vehicleData);
  }
}
