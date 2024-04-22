import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:microflutter/screens/register.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart';
import 'home.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _errorMessage = "";

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final response = await http.post(
      Uri.parse(baseUrl + '/user/login'), 
      headers: {
          'Content-Type': 'application/json', 
      },
      body: jsonEncode({
        'email': _emailController.text,
        'password': _passwordController.text,
      }),

    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) { // Если запрос успешен
      final jwtToken = data['details']; // Извлекаем JWT-токен
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', jwtToken); 
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(jwtToken: jwtToken)), // Передаем токен
      );
    } else {
      setState(() {
        _errorMessage = data['details']; // Сообщение об ошибке
      });
    }
  }

  void _goToregister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Получаем ширину экрана
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text("Login"),
      ),
      body: Center( // Центрируем по вертикали и горизонтали
        child: Container( 
          width: screenWidth * 0.6, // 60% ширины экрана
          padding: EdgeInsets.all(16), // Отступы внутри контейнера
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.5),
                spreadRadius: 5,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'Email'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                if (_errorMessage.isNotEmpty) // Проверяем, есть ли сообщение об ошибке
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _errorMessage, // Отображаем сообщение об ошибке
                      style: TextStyle(color: Colors.red), // Цвет текста для ошибок
                    ),
                  ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end, 
                  children: [
                      ElevatedButton(
                        onPressed: _goToregister,
                        child: Text("Registration"),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _login,
                        child: Text("Login"),
                      ),
                  ]
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
