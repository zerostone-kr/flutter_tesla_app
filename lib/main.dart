import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';


void main() {

  const String clientId = String.fromEnvironment('CLIENT_ID');
  const String clientSecret = String.fromEnvironment('CLIENT_SECRET');

  print('CLIENT_ID : $clientId');
  print('CLIENT_SECRET : $clientSecret');

  runApp(MyApp(clientId: clientId, clientSecret: clientSecret));
}

class MyApp extends StatelessWidget {
  final String clientId;
  final String clientSecret;

  MyApp({required this.clientId, required this.clientSecret});

  @override
  Widget build(BuildContext context) {
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

class _MyHomePageState extends State<MyHomePage> {
  String accessToken = '';
  HttpServer? _server; // HttpServer 객체 선언
  final String redirectUri = 'http://localhost:8080/callback';
  final String scope = 'openid offline_access user_data vehicle_device_data vehicle_cmds vehicle_charging_cmds';

  @override
  void initState() {
    super.initState();
    _startLocalServer(); // 로컬 서버 시작
    _loadAccessToken(); // 저장된 액세스 토큰 로드
  }

  @override
  void dispose() {
    _closeLocalServer(); // 리소스 해제
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080, shared: true);
      print('[zerostone] Local server started on port: 8080');
      
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

  void _closeLocalServer() {
    _server?.close(force: true).then((_) {
      print('[zerostone] Local server closed');
    }).catchError((error) {
      print('[zerostone] Error closing server: $error');
    });
  }

  Future<void> _fetchAccessToken(String code) async {
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
        'scope': scope,
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      setState(() {
        accessToken = responseData['access_token'];
      });
      print('[zerostone] Token fetched successfully: $accessToken');
      _saveAccessToken(accessToken);
    } else {
      print('[zerostone] Failed to fetch access token: ${response.statusCode}');
      print('[zerostone] Response body: ${response.body}');
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
    if (accessToken.isEmpty) {
      _startAuthentication();
    } else {
      print('[zerostone] Access token loaded: $accessToken');
    }
  }

  Future<void> _clearAccessToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    setState(() {
      accessToken = '';
    });
  }

  void _startAuthentication() {
    // 만약 accessToken이 없으면, 인증 URL로 이동
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text('Authenticate')),
          body: WebView(
            initialUrl: 'https://auth.tesla.com/oauth2/v3/authorize'
                '?response_type=code&client_id=${widget.clientId}'
                '&redirect_uri=$redirectUri&scope=$scope',
            javascriptMode: JavascriptMode.unrestricted,
            onPageStarted: (url) {
              print('[zerostone] Loading URL: $url');
            },
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tesla API Demo'),
        actions: [
          IconButton(
            icon: Icon(Icons.directions_car),
            onPressed: () {
              print('[zerostone] 자동차 정보 버튼 클릭됨');
            },
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _clearAccessToken,
                        child: Text('신규토큰발행'),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {
                          _clearAccessToken();
                          print('[zerostone] 저장된 토큰 삭제됨');
                        },
                        child: Text('저장토큰삭제'),
                      ),
                    ],
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
                  print('Error starting local server: ${snapshot.error}');
                  return Center(
                    child: Text('Failed to start local server: ${snapshot.error}'),
                  );
                } else {
                  if (accessToken.isEmpty) {
                    return Center(
                      child: Text('No access token found. Please authenticate.'),
                    );
                  } else {
                    return Center(
                      child: Text('Authentication complete.'),
                    );
                  }
                }
              },
            )


    );
  }
}
