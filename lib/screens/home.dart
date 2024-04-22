import 'dart:async';
import 'dart:convert'; // Для разбора JSON
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart'; // Библиотека для графиков
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart'; 
import 'auth.dart';

class HomeScreen extends StatefulWidget {
  final String jwtToken;

  HomeScreen({required this.jwtToken});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedMaster; // Выбранный мастер
  int? _selectedSensor; // Выбранный датчик
  List<dynamic> _masters = []; // Список мастеров
  List<dynamic> _sensors = []; // Список датчиков
  DateTime _fromDate = DateTime.now().subtract(Duration(days: 1)); // Дата начала
  DateTime _toDate = DateTime.now(); // Дата конца
  List<String> _names = [];
  List<LineChartBarData> _chartData = [];
  bool _isLoading = true;
  bool _nowMode = true;
  final formatter = DateFormat('MM-dd HH:mm');
  final formatterFull = DateFormat('yyyy-MM-dd HH:mm');
  Timer? _timer;
  late ScrollController _scrollController = ScrollController();
  String formatTimestamp(int timestamp, DateFormat formatter) {
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return formatter.format(date);
  }

  @override
  void dispose() {
    _stopTimer(); // Остановить таймер при удалении виджета
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    _loadMasters();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(seconds: 10),
      (timer) {
        if (_nowMode) {
          if (_toDate.isBefore(DateTime.now())) {
            setState(() {
              _toDate = DateTime.now();
            });
          }
          _loadData();
        }
      }
    );
  }

  void _stopTimer() {
    _timer?.cancel();
  }


  // Загрузка мастеров
  void _loadMasters() async {
    final response = await http.get(
      Uri.parse(baseUrl + "/master/list"),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );
    if (response.statusCode == 200) {
      setState(() {
        _masters = jsonDecode(response.body);
        _selectedMaster = _masters.isNotEmpty ? _masters[0]["id"] : null;
        if (_selectedMaster != null) {
          _loadSensors(_selectedMaster!);
        }
      });
    }
  }

  // Загрузка датчиков для выбранного мастера
  void _loadSensors(int masterId) async {
    final response = await http.get(
      Uri.parse(baseUrl + "/master/sensors?master_id=$masterId"),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );
    if (response.statusCode == 200) {
      setState(() {
        _sensors = jsonDecode(response.body);
        _selectedSensor = _sensors.isNotEmpty ? _sensors[0]["id"] : null;
      });
      _loadData();
    }
  }

  
  Future<DateTime> _selectDateTime(BuildContext context) async {
    // Выбор даты
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return DateTime.now(); // Если пользователь отменил выбор даты
    }

    // Выбор времени
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
    );

    if (pickedTime == null) {
      return DateTime.now(); // Если пользователь отменил выбор времени
    }

    // Комбинируем дату и время
    final DateTime combinedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    return combinedDateTime;
  }

  void _loadData() async {
    if (_selectedMaster == null || _selectedSensor == null) {
      return; 
    }
    _loadNames(_selectedMaster!, _selectedSensor!, _fromDate.millisecondsSinceEpoch, _toDate.millisecondsSinceEpoch);
  }

  void _loadNames(int masterId, int sensorId, int from, int to) async {
    /*setState(() {
      _isLoading = true;
    });*/

    final response = await http.get(
      Uri.parse(
        baseUrl + '/master/data/names?from=$from&to=$to&master_id=$masterId&sensor_id=$sensorId',
      ),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );

    if (response.statusCode == 200) {
      setState(() {
        _names = List<String>.from(json.decode(response.body));
        _loadChartData(masterId, sensorId, from, to);
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _loadChartData(int masterId, int sensorId, int from, int to) async {
    List<LineChartBarData> chartLines = [];

    for (String name in _names) {
      final response = await http.get(
        Uri.parse(
          baseUrl + '/master/data?from=$from&to=$to&master_id=$masterId&sensor_id=$sensorId&name=$name',
        ),
        headers: {
          'Authorization': 'Bearer ${widget.jwtToken}'
        }
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);

        List<FlSpot> spots = data
          .where((entry) => entry["status"] == 0) // Отсеивание статуса, не равного нулю
          .map((entry) => FlSpot(
              DateTime.fromMillisecondsSinceEpoch(entry["timestamp"]).millisecondsSinceEpoch.toDouble(),
              entry["value"].toDouble()))
          .toList();

        chartLines.add(
          LineChartBarData(
            color: Theme.of(context).colorScheme.tertiary,
            spots: spots,
            isCurved: false,
            barWidth: 2,
          ),
        );
      }
    }

    setState(() {
      _chartData = chartLines;
    });
  }

  Widget _buildChart(LineChartBarData chartData) {
    double width = MediaQuery.of(context).size.width;
    
    //double intervalz = _toDate.difference(_fromDate).inMilliseconds / 5 * (1200 / width) / 2;
    double intervalz = 1 + (chartData.spots.last.x - chartData.spots.first.x) / 4 * ((600 / width) + 1).round();
    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((touchedSpot) {
                return LineTooltipItem(
                  '${touchedSpot.y} \n ${formatTimestamp(touchedSpot.x.toInt(), formatterFull)}',
                  TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [chartData],
        titlesData: FlTitlesData(
          show: true,
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false)
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32, // Размер пространства для меток
              interval: 5, // Интервал между метками на оси Y
              getTitlesWidget: (value, meta) {
                return Text(value.toStringAsFixed(1)); // Пример простого отображения чисел
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32, // Размер пространства для меток
              interval: 5, // Интервал между метками на оси Y
              getTitlesWidget: (value, meta) {
                return Text(value.toStringAsFixed(1)); // Пример простого отображения чисел
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: intervalz,
              getTitlesWidget: (value, meta) {
                if (value == chartData.spots.last.x || value == chartData.spots.first.x) {
                  return SizedBox.shrink();
                }
                return Text(formatTimestamp(value.toInt(), formatter));
              },
            )
          ),
        ),
      ),
    );
  }
  /*Widget _buildChart(LineChartBarData chartData) {
    return LineChart(
      LineChartData(
        lineBarsData: [chartData],
        titlesData: FlTitlesData(
          show: true,
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(formatTimestamp(value.toInt()));
              },
            ),
          ),
        ),
      ),
    );
  }*/
  Future<void> _showToken() async {
    final response = await http.get(
      Uri.parse(baseUrl + "/master/token?master_id=${_selectedMaster!}"),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );
    final String token = response.body.replaceAll('"', '');
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text("$token (tap to copy)"),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  TextEditingController? _editMasterController;// = TextEditingController(text: _masters.firstWhere((x) => x['id'] == _selectedMaster!)["name"]);
  Future<void> _editMaster() async {
    if (_selectedMaster == null) {
      return;
    }
    _editMasterController = TextEditingController(text: _masters.firstWhere((x) => x['id'] == _selectedMaster!)["name"]);
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child:
                TextField(
                  controller: _editMasterController,
                  decoration: InputDecoration(
                    hintText: "New name here...",
                    labelText: "Rename master controller",
                    border: OutlineInputBorder(),
                    //prefixIcon: Icon(),
                  ),
                ),
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: () async {
                  final response = await http.get(
                    Uri.parse(baseUrl + "/master/rename?master_id=${_selectedMaster!}&name=${_editMasterController!.text}"),
                    headers: {
                      'Authorization': 'Bearer ${widget.jwtToken}'
                    }
                  );
                  if (response.statusCode == 200) {
                    setState(() {
                      _masters.firstWhere((x) => x['id'] == _selectedMaster!)["name"] = _editMasterController!.text;
                    });
                  }
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  TextEditingController? _addMasterController;// = TextEditingController(text: _masters.firstWhere((x) => x['id'] == _selectedMaster!)["name"]);
  Future<void> _addMaster() async {
    _addMasterController = TextEditingController(text: "master1");
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child:
                TextField(
                  controller: _addMasterController,
                  decoration: InputDecoration(
                    hintText: "New master name here...",
                    labelText: "Create master controller",
                    border: OutlineInputBorder(),
                    //prefixIcon: Icon(),
                  ),
                ),
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: () async {
                  final response = await http.get(
                    Uri.parse(baseUrl + "/master/create?name=${_addMasterController!.text}"),
                    headers: {
                      'Authorization': 'Bearer ${widget.jwtToken}'
                    }
                  );
                  if (response.statusCode == 200) {
                    setState(() {
                      _loadMasters();
                    });
                  }
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  TextEditingController? _editSensorController;
  Future<void> _editSensor() async {
    if (_selectedSensor == null) {
      return;
    }
    _editSensorController = TextEditingController(text: _sensors.firstWhere((x) => x['id'] == _selectedSensor!)["name"]);
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child:
                TextField(
                  controller: _editSensorController,
                  decoration: InputDecoration(
                    hintText: "New name here...",
                    labelText: "Rename sensors",
                    border: OutlineInputBorder(),
                    //prefixIcon: Icon(),
                  ),
                ),
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.edit),
                onPressed: () async {
                  final response = await http.get(
                    ///sensor/rename
                    Uri.parse(baseUrl + "/master/sensor_rename?master_id=${_selectedMaster!}&sensor_id=${_selectedSensor!}&name=${_editSensorController!.text}"),
                    headers: {
                      'Authorization': 'Bearer ${widget.jwtToken}'
                    }
                  );
                  if (response.statusCode == 200) {
                    setState(() {
                      _sensors.firstWhere((x) => x['id'] == _selectedSensor!)["name"] = _editSensorController!.text;
                    });
                  }
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  

  void _showMasterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 150,
                ),
                child:
                ListView.builder(
                  itemCount: _masters.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: Icon(Icons.home),
                      title: Text("Select ${_masters[index]["name"]}"),
                      onTap: () {
                        setState(() {
                            _selectedMaster = _masters[index]["id"];
                            _loadSensors(_selectedMaster!);
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                )
              ),
            ],
          ),
        );
      },
    );
  }

   void _showSensorOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 150,
                ),
                child:
                ListView.builder(
                  itemCount: _sensors.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: Icon(Icons.home),
                      title: Text("Select ${_sensors[index]["name"]}"),
                      onTap: () {
                        setState(() {
                            _selectedSensor = _sensors[index]["id"];
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                )
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double fontSize = 12 + screenWidth * 0.003;
    return Scaffold(
      /*appBar: AppBar(
        title: Text("Data Screen"),
      ),*/
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.only(left: 20, right: 5, top: 10),
            child: Row(children: [
              Text(_selectedMaster == null ? "Create master" : _masters.firstWhere((x) => x['id'] == _selectedMaster!)["name"],
                style: TextStyle(
                  fontSize: fontSize + 7, 
                  color: Theme.of(context).colorScheme.tertiary,
                  fontWeight: FontWeight.bold
                )
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.lock),
                onPressed: _showToken
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: _addMaster
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.edit_outlined),
                onPressed: _editMaster
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.arrow_drop_down_outlined),
                onPressed: _showMasterOptions
              ),
            ]),
          ),
          Container(
            margin: EdgeInsets.only(left: 20, right: 5, top: 10),
            child: Row(children: [
              Text(_selectedSensor == null ? "No sensor" : _sensors.firstWhere((x) => x['id'] == _selectedSensor!)["name"],
                style: TextStyle(
                  fontSize: fontSize + 7, 
                  color: Theme.of(context).colorScheme.tertiary,
                  fontWeight: FontWeight.bold
                )
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.edit_outlined),
                onPressed: _editSensor
              ),
              SizedBox(width: 10),
              IconButton(
                icon: Icon(Icons.arrow_drop_down_outlined),
                onPressed: _showSensorOptions
              ),
            ]),
          ),
          SizedBox(height: 10),
          Divider(
            //color: Colors.blue, // Цвет разделителя
            thickness: 1, // Толщина линии
            indent: 16, // Отступ слева
            endIndent: 16, // Отступ справа
          ),
          // Выбор мастера
          /*DropdownButton<int>(
            value: _selectedMaster,
            items: _masters
                .map((master) => DropdownMenuItem(
                      value: master["id"] as int,
                      child: Text(master["name"]),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedMaster = value;
                _loadSensors(value!);
              });
            },
          ),
          // Выбор датчика
          if (_sensors.isNotEmpty)
            DropdownButton<int>(
              value: _selectedSensor,
              items: _sensors
                  .map((sensor) => DropdownMenuItem(
                        value: sensor["id"] as int,
                        child: Text(sensor["name"]),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedSensor = value;
                });
              },
            ),*/
          Expanded(child: 
            ListView(children: [
              Row(children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: EdgeInsets.only(left: 10, right: 5, top: 10),
                    child: ElevatedButton(
                      child: Text("From ${formatter.format(_fromDate)}", style: TextStyle(fontSize: fontSize)),
                      onPressed: () async {
                        _nowMode = false;
                        var date = await _selectDateTime(context);
                        setState(() {
                          _fromDate = date;
                        });
                      },
                    )
                  ),
                  
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: EdgeInsets.only(left: 5, right: 10, top: 10),
                    child: ElevatedButton(
                      child: Text("To ${formatter.format(_toDate)}", style: TextStyle(fontSize: fontSize)),
                      onPressed: () async {
                        var date = await _selectDateTime(context);
                        _nowMode = date.isAfter(DateTime.now());
                        setState(() {
                          _toDate = date;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: EdgeInsets.only(left: 10, right: 5, top: 10),
                      child: ElevatedButton(
                        child: Text("Now", style: TextStyle(fontSize: fontSize)),
                        onPressed: () async {
                          setState(() {
                            _toDate = DateTime.now();
                          });
                        _nowMode = true;
                          _loadData();
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: EdgeInsets.only(left: 5, right: 10, top: 10),
                      child: ElevatedButton(
                        onPressed: _loadData, // Загрузка данных при нажатии
                        child: Text("Load Data", style: TextStyle(fontSize: fontSize)),
                      ),
                    ),
                  )
              ]
            ),
            _isLoading ? CircularProgressIndicator() : ListView.builder(
              shrinkWrap: true,
              controller: _scrollController, 
              key: PageStorageKey('const name here'),
              itemCount: _chartData.length,
              itemBuilder: (context, index) {
                return Container(
                  //key: ValueKey(_names[index]),
                  margin: EdgeInsets.symmetric(vertical: 0, horizontal: fontSize - 5),
                  padding: EdgeInsets.all(16), // Отступы для каждого графика
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      Text("${_names[index]}"), // Заголовок графика
                      SizedBox(height: 10), // Пробел между заголовком и графиком
                      SizedBox(
                        height: 200, // Высота виджета с графиком
                        child: _buildChart(_chartData[index]), // Построение графика
                      ),
                    ],
                  ),
                );
              },
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: EdgeInsets.only(left: 10, right: 5, top: 10),
                child: IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () async {
                    await _logOut();
                  },
                ),
              ),
            ),
            SizedBox(height: 20),
          ]),
        ),
      ]),
    );
  }
  
  Future<void> _logOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token'); 
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => AuthScreen(), // Страница авторизации
      ),
      (route) => false, // Условие, которое всегда возвращает false
    );
  }
}
