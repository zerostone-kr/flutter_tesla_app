import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final String clientId = dotenv.env['CLIENT_ID'] ?? '';
    final String clientSecret = dotenv.env['CLIENT_SECRET'] ?? '';

    return MaterialApp(
      title: 'Tesla API Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(clientId: clientId, clientSecret: clientSecret),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String clientId;
  final String clientSecret;

  MyHomePage({required this.clientId, required this.clientSecret});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  WebViewController? _controller;
  String accessToken = '';
  HttpServer? _server;
  final int _port = 8080;  // 포트 8080 사용
  bool _isFetchingToken = false;  // 중복 실행 방지

  final String redirectUri = 'http://localhost:8080/callback';  // 리디렉션 URI
  final String scope = 'openid offline_access user_data vehicle_device_data vehicle_cmds vehicle_charging_cmds';

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
        print('[zerostone] Local server closed');
      }).catchError((error) {
        print('[zerostone] Error closing server: $error');
      });
      _server = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _closeLocalServer();
    }
  }

  Future<void> _startLocalServer() async {
    if (_server != null) {
      return;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port, shared: true);
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

  Future<void> _fetchAccessToken(String code) async {
    if (_isFetchingToken) return;
    _isFetchingToken = true;

    final response = await http.post(
      Uri.parse('https://auth.tesla.com/oauth2/v3/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'client_id': widget.clientId,
        'client_secret': widget.clientSecret,
        'code': code,
        'redirect_uri': redirectUri,
        'scope': scope,  // Scope 추가
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      setState(() {
        accessToken = responseData['access_token'];
      });
      print('[zerostone] Token fetched successfully: $accessToken');  // 토큰 발행 로그 추가
      _saveAccessToken(accessToken);
      _closeLocalServer();  // 로컬 서버 종료
      _getVehicleData();
    } else {
      print('[zerostone] Failed to fetch access token: ${response.statusCode}');
      print('[zerostone] Response body: ${response.body}');
    }

    _isFetchingToken = false;
  }

  Future<void> _getVehicleData() async {
    if (accessToken.isEmpty) {
      print('[zerostone] Access token is empty');
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
      print('[zerostone] $vehicleData');
    } else {
      print('[zerostone] Failed to fetch vehicle data: ${response.statusCode}');
      print('[zerostone] Response body: ${response.body}');
      if (response.statusCode == 401) {
        print('[zerostone] Invalid bearer token');
        await _clearAccessToken();
        _startLocalServer();  // 로컬 서버 다시 시작
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
    } else {
      _startLocalServer();
    }
  }

  Future<void> _clearAccessToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    setState(() {
      accessToken = '';
    });
    await Future.delayed(Duration(seconds: 1)); // 딜레이 추가
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
                          initialUrl: 'https://auth.tesla.com/oauth2/v3/authorize?response_type=code&client_id=${widget.clientId}&redirect_uri=$redirectUri&scope=$scope',
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
