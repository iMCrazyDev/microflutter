import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../globals.dart';
import 'home.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  var _errorMessage = "";

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final response = await http.post(
      Uri.parse(baseUrl + '/user/register'), 
      headers: {
          'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': _emailController.text,
        'password': _passwordController.text,
        'name': _nameController.text,
      }),

    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) { 
      final jwtToken = data['details'];
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

  void _goToLogin() {
    Navigator.pop(context);
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
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Name'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
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
                        onPressed: _goToLogin,
                        child: Text("Login"),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _register,
                        child: Text("Register"),
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
