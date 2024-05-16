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
    if (response.statusCode == 200) {
      final jwtToken = data['details'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', jwtToken); 
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(jwtToken: jwtToken)),
      );
    } else {
      setState(() {
        _errorMessage = data['details'];
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text("Login"),
      ),
      body: Center( 
        child: Container( 
          width: screenWidth * 0.9,
          padding: EdgeInsets.all(16),
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
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red),
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
