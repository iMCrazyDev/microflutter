import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart'; 
import 'auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HomeScreen extends StatefulWidget {
  final String jwtToken;

  HomeScreen({required this.jwtToken});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedMaster;
  int? _selectedSensor;
  List<dynamic> _masters = [];
  List<dynamic> _sensors = [];
  DateTime _fromDate = DateTime.now().subtract(Duration(days: 1));
  DateTime _toDate = DateTime.now();
  List<String> _names = [];
  List<LineChartBarData> _chartData = [];
  List<String> _chartUnits = [];
  bool _isLoading = true;
  bool _noData = false;
  bool _nowMode = true;
  bool _haveMapPoints = false;
  List<LatLng> _mapPoints = [];
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
    _stopTimer();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    _loadMasters();
    _startTimer();
  }

  Future<void> _initLastTs(int master_id) async {
    final response = await http.get(
      Uri.parse(baseUrl + "/master/last_timestamp?master_id=$master_id"),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );
    if (response.statusCode == 200) {
      setState(() {
        //_toDate = DateTime.fromMillisecondsSinceEpoch(int.parse(response.body));
        _fromDate = DateTime.fromMillisecondsSinceEpoch(int.parse(response.body)).subtract(Duration(days: 1));
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(
      Duration(seconds: 10),
      (timer) {
        if (_nowMode || _noData) {
          if (_toDate.isBefore(DateTime.now())) {
            setState(() {
              _toDate = DateTime.now();
            });
          }
          if (_selectedSensor == null && _selectedMaster != null) {
            _loadSensors(_selectedMaster!);
          }
          if (_selectedMaster != null && _selectedSensor != null) {
            _loadData();
          }
        }
      }
    );
  }

  void _stopTimer() {
    _timer?.cancel();
  }


  void _loadMasters() async {
    final response = await http.get(
      Uri.parse(baseUrl + "/master/list"),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );
    if (response.statusCode == 200) {
      _masters = jsonDecode(response.body);
      _selectedMaster = _masters.isNotEmpty ? _masters[0]["id"] : null;
      if (_selectedMaster != null) {
        await _initLastTs(_selectedMaster!);
      }
      else {
        setState(() {
        _noData = true;
        _isLoading = false;
        });
      }
      setState(() {
        _masters;
        _selectedMaster;
        if (_selectedMaster != null) {
          _loadSensors(_selectedMaster!);
        }
      });
    }
  }

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
      var listLocations = _sensors.where((point) => point['latitude'] != null && point['latitude'] != 0 && point['longitude'] != null && point['longitude'] != 0);
      var have = !listLocations.isEmpty;
      setState(() {
        _haveMapPoints = have;
        _mapPoints = listLocations.map((point) => LatLng(point['latitude'], point['longitude'])).toList();
      });
      if (response.body == "[]") {
        setState(() {
          _noData = true;
          _isLoading = false;
        });
      } else {
        _loadData(forceLoading: true);
      }
    }
  }

  LatLng calculateCenter(List<LatLng> points) {
    double totalLat = 0;
    double totalLng = 0;

    for (var point in points) {
      totalLat += point.latitude;
      totalLng += point.longitude;
    }

    double avgLat = totalLat / points.length;
    double avgLng = totalLng / points.length;

    return LatLng(avgLat, avgLng);
  }

  double calculateMaxDistance(List<LatLng> positions) {
    final distance = Distance();
    double maxDistance = 0;

    // Вычисление максимального расстояния между всеми точками
    for (var pos1 in positions) {
      for (var pos2 in positions) {
        final currentDistance = distance.as(LengthUnit.Kilometer, pos1, pos2);
        if (currentDistance > maxDistance) {
          maxDistance = currentDistance;
        }
      }
    }

    return maxDistance;
  }
  
  Future<DateTime> _selectDateTime(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return DateTime.now(); // Если пользователь отменил выбор даты
    }


    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
    );

    if (pickedTime == null) {
      return DateTime.now(); // Если пользователь отменил выбор времени
    }

    final DateTime combinedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    return combinedDateTime;
  }

  void _loadData({bool forceLoading = false}) async {
    if (forceLoading || _noData) {
      setState(() {
        _isLoading = true;
      });
    }
    if (_selectedMaster == null || _selectedSensor == null) {
      return; 
    }
    _loadNames(_selectedMaster!, _selectedSensor!, _fromDate.millisecondsSinceEpoch, _toDate.millisecondsSinceEpoch);
  }

  void _loadNames(int masterId, int sensorId, int from, int to) async {
    /*setState(() {
      _isLoading = true;
    });*/
    //print(widget.jwtToken);
    final response = await http.get(
      Uri.parse(
        baseUrl + '/master/data/names?from=$from&to=$to&master_id=$masterId&sensor_id=$sensorId',
      ),
      headers: {
        'Authorization': 'Bearer ${widget.jwtToken}'
      }
    );

    if (response.statusCode == 200) {
      _names = List<String>.from(json.decode(response.body));
      _names.sort();
      await _loadChartData(masterId, sensorId, from, to);
      setState(() {
        _names;
        //_loadChartData(masterId, sensorId, from, to);
      });
    } else {
      setState(() {
        _noData = true;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  List<FlSpot> applyMovingAverage(List<FlSpot> data, int windowSize) {
    List<FlSpot> smoothedData = [];
    for (int i = 0; i < data.length - windowSize; i++) {
      double sumX = 0;
      double sumY = 0;

      for (int j = 0; j < windowSize; j++) {
        sumX += data[i + j].x;
        sumY += data[i + j].y;
      }

      double averageX = sumX / windowSize;
      double averageY = sumY / windowSize;

      smoothedData.add(FlSpot(averageX, averageY));
    }

    return smoothedData;
  }

  List<FlSpot> decimateData(List<FlSpot> data, int n) {
    List<FlSpot> reducedData = [];
    double step = data.length / n; // Интервал выборки
    for (int i = 0; i < n; i++) {
      int index = (i * step).round();
      if (index < data.length) {
        reducedData.add(data[index]);
      }
    }
    return reducedData;
  }


  Future<void> _loadChartData(int masterId, int sensorId, int from, int to) async {
    List<LineChartBarData> chartLines = [];
    _chartUnits.clear();
    if (_names.isEmpty) {
        setState(() {
          _noData = true;
        });
    }
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
        if (data.isEmpty) {
          setState(() {
            _noData = true;
          });
          
          return;
        }
        
        _chartUnits.add(data[0]["units"] ?? "");
        List<dynamic> data_sorted = data
          .where((entry) => entry["status"] == 0)
          .toList();
        data_sorted.sort((a, b) => a["timestamp"].compareTo(b["timestamp"]));
        List<FlSpot> spots = data_sorted.map((entry) => FlSpot(
            DateTime.fromMillisecondsSinceEpoch(entry["timestamp"]).millisecondsSinceEpoch.toDouble(),
            entry["value"].toDouble())).toList();
        spots = decimateData(applyMovingAverage(spots, min(30, spots.length)), 100);
        setState(() {
          if (spots.isEmpty) {
            _noData = true;
            return;
          }
          else {
            _noData = false;
          }
        });
        chartLines.add(
          LineChartBarData(
            color: Theme.of(context).colorScheme.tertiary,
            spots: spots,
            //isCurved: true,
            barWidth: 1,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 2, // Размер точки
                  //color: Colors.blue,
                  //strokeWidth: 2, // Толщина границы
                  //strokeColor: Colors.white, // Цвет границы
                );
              },
            ),
          ),
        );
      }
    }
    
    setState(() {
      _chartData = chartLines;
    });
  }

  Widget _buildChart(LineChartBarData chartData, int index) {
    double width = MediaQuery.of(context).size.width;
    
    //double intervalz = _toDate.difference(_fromDate).inMilliseconds / 5 * (1200 / width) / 2;
    double intervalz = 30000;
    try { intervalz = 1 + (chartData.spots.last.x - chartData.spots.first.x) / 4 * ((600 / width) + 1).round();
    }
    catch (Exc) {}
    return LineChart(
      LineChartData(
        minY: chartData.spots.map((spot) => spot.y).reduce((a, b) => a < b ? a : b) - 1,
        maxY: chartData.spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) + 1,                                   
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((touchedSpot) {
                return LineTooltipItem(
                  '${touchedSpot.y.toStringAsFixed(3)} ${_chartUnits[index]}\n${formatTimestamp(touchedSpot.x.toInt(), formatterFull)}',
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
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: 100,
              getTitlesWidget: (value, meta) {
                return Text(value.toStringAsFixed(1));
              },
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: 100,
              getTitlesWidget: (value, meta) {
                return Text(value.toStringAsFixed(1));
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
    _addMasterController = TextEditingController(text: "hub1");
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
                    hintText: "New hub name here...",
                    labelText: "Create hub controller",
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
                      onTap: () async {
                        if (!_noData && _masters[index]["id"] == _selectedMaster) {
                          Navigator.pop(context);
                          return;
                        }
                        _selectedMaster = _masters[index]["id"];
                        await _initLastTs(_selectedMaster!);
                        setState(() {
                          _selectedMaster;
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
                        if (!_noData && _sensors[index]["id"] == _selectedSensor) {
                          Navigator.pop(context);
                          return;
                        }
                        setState(() {
                            _selectedSensor = _sensors[index]["id"];
                        });
                        _loadData(forceLoading: true);
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
              Text(_selectedMaster == null ? "Create hub" : _masters.firstWhere((x) => x['id'] == _selectedMaster!)["name"],
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
            //color: Colors.blue,
            thickness: 1,
            indent: 16,
            endIndent: 16,
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
                          if (_selectedMaster != null) {
                            await _initLastTs(_selectedMaster!);
                          }
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
                        onPressed: _loadData,
                        child: Text("Load Data", style: TextStyle(fontSize: fontSize)),
                      ),
                    ),
                  )
              ]
            ),
            _haveMapPoints ? Container(
              padding: EdgeInsets.all(16),
              height: 300,  // can be virtually anything
              child: FlutterMap(
                options: MapOptions(
                  center: calculateCenter(_mapPoints), // Центральная точка карты (Париж)
                  zoom: 17 - (calculateMaxDistance(_mapPoints) / 100), // Уровень зума
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.microflutter.app',
                  ),
                  MarkerLayer(
                    markers: _sensors.where((point) => point['latitude'] != null && point['latitude'] != 0 && point['longitude'] != null && point['longitude'] != 0).map((point) {
                      return Marker(
                        point: LatLng(point['latitude'], point['longitude']),
                        child: GestureDetector(
                          child: Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 40
                          ),
                          onTap: () {
                            if (point["id"] == _selectedSensor) {
                              return;
                            }
                            setState(() {
                                _selectedSensor = point["id"];
                            });
                            _loadData(forceLoading: true);
                          }
                        )
                      );
                    }).toList(),
                  ),
                ],
              )
            ) : SizedBox.shrink(),
            _isLoading ? Container(alignment: Alignment.center, padding: EdgeInsets.all(32), child: CircularProgressIndicator()) :
            _noData ? Container(alignment: Alignment.center, padding: EdgeInsets.all(32), child: Text("No data")) : ListView.builder(
              shrinkWrap: true,
              controller: _scrollController, 
              key: PageStorageKey('const name here'),
              itemCount: _chartData.length,
              itemBuilder: (context, index) {
                return Container(
                  //key: ValueKey(_names[index]),
                  margin: EdgeInsets.symmetric(vertical: 0, horizontal: fontSize - 5),
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      Text("${_names[index]}"),
                      SizedBox(height: 10),
                      SizedBox(
                        height: 200,
                        child: _buildChart(_chartData[index], index),
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
        builder: (context) => AuthScreen(),
      ),
      (route) => false,
    );
  }
}
