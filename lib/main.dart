import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  WebViewController? _controller;
  String accessToken = '';
  HttpServer? _server;
  final int _port = 8080;  // 포트 8080 사용

  // 제공된 clientId 및 clientSecret
  final String clientId = '2110d263-ec90-42b5-9fd9-e1064d93a976';
  final String clientSecret = 'ta-secret.GUwR%lb%N7UnHTeb';
  final String redirectUri = 'http://localhost:8080/callback';  // 리디렉션 URI

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccessToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeLocalServer();
    super.dispose();
  }

  void _closeLocalServer() {
    if (_server != null) {
      _server!.close(force: true).then((_) {
        print('Local server closed');
      }).catchError((error) {
        print('Error closing server: $error');
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _closeLocalServer();
    }
  }

  Future<void> _startLocalServer() async {
    try {
      _server?.close(force: true);  // 기존 서버가 있다면 먼저 종료
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port, shared: true);
      print('Local server started on port: $_port');
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
      print('Failed to start local server: $e');
    }
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
      _saveAccessToken(accessToken);
      _closeLocalServer();  // 로컬 서버 종료
      _getVehicleData();
    } else {
      print('Failed to fetch access token: ${response.statusCode}');
      print('Response body: ${response.body}');
    }
  }

  Future<void> _getVehicleData() async {
    if (accessToken.isEmpty) {
      print('Access token is empty');
      return;
    }

    final response = await http.get(
      Uri.parse('https://owner-api.teslamotors.com/api/1/vehicles'),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode == 200) {
      final vehicleData = json.decode(response.body);
      print(vehicleData);
    } else {
      print('Failed to fetch vehicle data: ${response.statusCode}');
      print('Response body: ${response.body}');
      if (response.statusCode == 401) {
        print('Invalid bearer token');
        _clearAccessToken();
      }
    }
  }

  Future<void> _saveAccessToken(String token) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
  }

  Future<void> _loadAccessToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      accessToken = prefs.getString('access_token') ?? '';
    });

    if (accessToken.isNotEmpty) {
      _getVehicleData();
    }
  }

  Future<void> _clearAccessToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    setState(() {
      accessToken = '';
    });
    _startLocalServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tesla API Demo'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _clearAccessToken,
          ),
        ],
      ),
      body: accessToken.isNotEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(child: Text('토큰이 존재합니다: $accessToken')),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: _clearAccessToken,
                    child: Text('신규토큰발행'),
                  ),
                ),
              ],
            )
          : FutureBuilder<void>(
              future: _startLocalServer(),
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(),
                  );
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text('Failed to start local server: ${snapshot.error}'),
                  );
                } else {
                  return Column(
                    children: [
                      Expanded(
                        child: WebView(
                          initialUrl: 'https://auth.tesla.com/oauth2/v3/authorize?response_type=code&client_id=$clientId&redirect_uri=$redirectUri&scope=openid email offline_access',
                          javascriptMode: JavascriptMode.unrestricted,
                          onWebViewCreated: (WebViewController webViewController) {
                            _controller = webViewController;
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton(
                          onPressed: _clearAccessToken,
                          child: Text('신규토큰발행'),
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
    );
  }
}