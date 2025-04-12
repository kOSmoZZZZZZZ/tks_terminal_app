import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, RegExp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().initDatabase();
  runApp(ContainerTerminalApp());
}

class ContainerTerminalApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primaryColor: Color(0xFFFF6200),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFFF6200),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: MainScreen(),
    );
  }
}

// Модель данных
class Zone {
  final int id;
  final String name;
  final double x;
  final double y;

  Zone({required this.id, required this.name, required this.x, required this.y});
}

class ContainerData {
  final int zoneId;
  final int x;
  final int y;
  final String? prefix;
  final String? number;

  ContainerData({
    required this.zoneId,
    required this.x,
    required this.y,
    this.prefix,
    this.number,
  });
}

// Локальная база данных
class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    String path = join(await getDatabasesPath(), 'tks_terminal.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE zones (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            x REAL,
            y REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE containers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            zone_id INTEGER,
            x INTEGER,
            y INTEGER,
            prefix TEXT,
            number TEXT
          )
        ''');
      },
    );
  }

  Future<void> insertZone(Zone zone) async {
    final db = await database;
    await db.insert('zones', {
      'name': zone.name,
      'x': zone.x,
      'y': zone.y,
    });
  }

  Future<void> deleteZone(int id) async {
    final db = await database;
    await db.delete('zones', where: 'id = ?', whereArgs: [id]);
    await db.delete('containers', where: 'zone_id = ?', whereArgs: [id]);
  }

  Future<List<Zone>> getZones() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('zones');
    return List.generate(maps.length, (i) {
      return Zone(
        id: maps[i]['id'],
        name: maps[i]['name'],
        x: maps[i]['x'],
        y: maps[i]['y'],
      );
    });
  }

  Future<void> insertContainer(ContainerData container) async {
    final db = await database;
    await db.insert('containers', {
      'zone_id': container.zoneId,
      'x': container.x,
      'y': container.y,
      'prefix': container.prefix,
      'number': container.number,
    });
  }

  Future<void> deleteContainer(int zoneId, int x, int y) async {
    final db = await database;
    await db.delete(
      'containers',
      where: 'zone_id = ? AND x = ? AND y = ?',
      whereArgs: [zoneId, x, y],
    );
  }

  Future<List<ContainerData>> getContainers(int zoneId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'containers',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
    );
    return List.generate(maps.length, (i) {
      return ContainerData(
        zoneId: maps[i]['zone_id'],
        x: maps[i]['x'],
        y: maps[i]['y'],
        prefix: maps[i]['prefix'],
        number: maps[i]['number'],
      );
    });
  }

  Future<ContainerData?> searchContainer(String prefix, String number) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'containers',
      where: 'prefix = ? AND number = ?',
      whereArgs: [prefix, number],
    );
    if (maps.isNotEmpty) {
      return ContainerData(
        zoneId: maps[0]['zone_id'],
        x: maps[0]['x'],
        y: maps[0]['y'],
        prefix: maps[0]['prefix'],
        number: maps[0]['number'],
      );
    }
    return null;
  }

  Future<void> updateContainer(ContainerData container) async {
    final db = await database;
    await db.update(
      'containers',
      {
        'x': container.x,
        'y': container.y,
        'prefix': container.prefix,
        'number': container.number,
      },
      where: 'zone_id = ? AND x = ? AND y = ?',
      whereArgs: [container.zoneId, container.x, container.y],
    );
  }

  Future<void> clearContainers(int zoneId) async {
    final db = await database;
    await db.delete('containers', where: 'zone_id = ?', whereArgs: [zoneId]);
  }
}

// Главный экран
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<Zone> zones = [];

  @override
  void initState() {
    super.initState();
    _loadZones();
    _requestPermissions();
  }

  void _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }
  }

  void _loadZones() async {
    zones = await DatabaseHelper().getZones();
    setState(() {});
  }

  void _addZone() async {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Новая зона (TKS)'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(labelText: 'Название зоны'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                final zone = Zone(
                  id: 0,
                  name: nameController.text,
                  x: 100.0 + zones.length * 10,
                  y: 100.0 + zones.length * 10,
                );
                await DatabaseHelper().insertZone(zone);
                _loadZones();
                Navigator.pop(context);
              }
            },
            child: Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _deleteZone(int id) async {
    await DatabaseHelper().deleteZone(id);
    _loadZones();
  }

  void _exportToExcel() async {
    if (await Permission.storage.isGranted) {
      var excel = Excel.createExcel();
      var zoneSheet = excel['Zones'];
      var containerSheet = excel['Containers'];

      zoneSheet.appendRow(['ID', 'Название', 'X', 'Y']);
      for (var zone in zones) {
        zoneSheet.appendRow([zone.id, zone.name, zone.x, zone.y]);
      }

      containerSheet.appendRow(['ID зоны', 'X', 'Y', 'Префикс', 'Номер']);
      for (var zone in zones) {
        var containers = await DatabaseHelper().getContainers(zone.id);
        for (var container in containers) {
          containerSheet.appendRow([
            container.zoneId,
            container.x,
            container.y,
            container.prefix,
            container.number,
          ]);
        }
      }

      final directory = await getExternalStorageDirectory();
      final filePath = '${directory!.path}/tks_terminal.xlsx';
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(excel.encode()!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспортировано в $filePath')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Требуется разрешение на доступ к хранилищу')),
      );
    }
  }

  void _importFromExcel() async {
    if (await Permission.storage.isGranted) {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result != null) {
        try {
          var bytes = File(result.files.single.path!).readAsBytesSync();
          var excel = Excel.decodeBytes(bytes);

          var zoneSheet = excel['Zones'];
          for (var row in zoneSheet.rows.skip(1)) {
            if (row.length >= 4) {
              await DatabaseHelper().insertZone(Zone(
                id: 0,
                name: row[1]?.value?.toString() ?? '',
                x: double.parse(row[2]?.value?.toString() ?? '0'),
                y: double.parse(row[3]?.value?.toString() ?? '0'),
              ));
            }
          }

          for (var zone in zones) {
            await DatabaseHelper().clearContainers(zone.id);
          }
          var containerSheet = excel['Containers'];
          for (var row in containerSheet.rows.skip(1)) {
            if (row.length >= 5) {
              await DatabaseHelper().insertContainer(ContainerData(
                zoneId: int.parse(row[0]?.value?.toString() ?? '0'),
                x: int.parse(row[1]?.value?.toString() ?? '0'),
                y: int.parse(row[2]?.value?.toString() ?? '0'),
                prefix: row[3]?.value?.toString(),
                number: row[4]?.value?.toString(),
              ));
            }
          }

          _loadZones();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Импорт успешен')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка импорта: $e')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Требуется разрешение на доступ к хранилищу')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Терминал TKS'),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      SearchScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.easeInOut;
                    var tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: curve));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    );
                  },
                  transitionDuration: Duration(milliseconds: 300),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.upload_file),
            onPressed: _importFromExcel,
          ),
          IconButton(
            icon: Icon(Icons.download),
            onPressed: _exportToExcel,
          ),
        ],
      ),
      body: CustomPaint(
        painter: ZonePainter(zones),
        child: GestureDetector(
          onTapDown: (details) {
            for (var zone in zones) {
              if ((details.localPosition.dx - zone.x).abs() < 50 &&
                  (details.localPosition.dy - zone.y).abs() < 50) {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        GridScreen(zone: zone),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      const begin = Offset(1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.easeInOut;
                      var tween = Tween(begin: begin, end: end)
                          .chain(CurveTween(curve: curve));
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                    transitionDuration: Duration(milliseconds: 300),
                  ),
                );
                return;
              }
            }
          },
          onLongPressStart: (details) {
            for (var zone in zones) {
              if ((details.localPosition.dx - zone.x).abs() < 50 &&
                  (details.localPosition.dy - zone.y).abs() < 50) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Удалить зону "${zone.name}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () {
                          _deleteZone(zone.id);
                          Navigator.pop(context);
                        },
                        child: Text('Удалить'),
                      ),
                    ],
                  ),
                );
                return;
              }
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addZone,
        child: Icon(Icons.add),
        backgroundColor: Color(0xFFFF6200),
      ),
    );
  }
}

class ZonePainter extends CustomPainter {
  final List<Zone> zones;

  ZonePainter(this.zones);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFFFF6200).withOpacity(0.7)
      ..style = PaintingStyle.fill;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var zone in zones) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(zone.x, zone.y), width: 100, height: 80),
          Radius.circular(8),
        ),
        paint,
      );
      textPainter.text = TextSpan(
        text: zone.name,
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(zone.x - textPainter.width / 2, zone.y - 50));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Экран поиска
class SearchScreen extends StatefulWidget {
  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final prefixController = TextEditingController();
  final numberController = TextEditingController();
  ContainerData? searchResult;
  Zone? foundZone;

  void _searchContainer() async {
    if (prefixController.text.length == 4 && numberController.text.length == 7) {
      final container = await DatabaseHelper().searchContainer(
        prefixController.text,
        numberController.text,
      );
      if (container != null) {
        final zones = await DatabaseHelper().getZones();
        foundZone = zones.firstWhere((zone) => zone.id == container.zoneId);
      }
      setState(() {
        searchResult = container;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Префикс — 4 буквы, номер — 7 цифр')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Поиск контейнера (TKS)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: prefixController,
              decoration: InputDecoration(labelText: 'Префикс (4 буквы)'),
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z]')),
              ],
            ),
            TextField(
              controller: numberController,
              decoration: InputDecoration(labelText: 'Номер (7 цифр)'),
              maxLength: 7,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _searchContainer,
              child: Text('Найти'),
            ),
            SizedBox(height: 16),
            if (searchResult != null && foundZone != null)
              Column(
                children: [
                  Text('Найден контейнер: ${searchResult!.prefix}${searchResult!.number}'),
                  Text('Зона: ${foundZone!.name}'),
                  Text('Позиция: (${searchResult!.x}, ${searchResult!.y})'),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) =>
                              GridScreen(zone: foundZone!),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            const begin = Offset(1.0, 0.0);
                            const end = Offset.zero;
                            const curve = Curves.easeInOut;
                            var tween = Tween(begin: begin, end: end)
                                .chain(CurveTween(curve: curve));
                            return SlideTransition(
                              position: animation.drive(tween),
                              child: child,
                            );
                          },
                          transitionDuration: Duration(milliseconds: 300),
                        ),
                      );
                    },
                    child: Text('Перейти к зоне'),
                  ),
                ],
              )
            else if (searchResult == null && prefixController.text.isNotEmpty)
              Text('Контейнер не найден'),
          ],
        ),
      ),
    );
  }
}

// Экран сетки
class GridScreen extends StatefulWidget {
  final Zone zone;

  GridScreen({required this.zone});

  @override
  _GridScreenState createState() => _GridScreenState();
}

class _GridScreenState extends State<GridScreen> {
  List<List<ContainerData?>> grid = List.generate(4, (_) => List.filled(5, null));
  int gridLength = 5;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  void _loadContainers() async {
    final containers = await DatabaseHelper().getContainers(widget.zone.id);
    setState(() {
      grid = List.generate(4, (_) => List.filled(gridLength, null));
      for (var container in containers) {
        if (container.y < 4 && container.x < gridLength) {
          grid[container.y][container.x] = container;
        }
      }
    });
  }

  void _addOrEditContainer(int x, int y) {
    final prefixController = TextEditingController(text: grid[y][x]?.prefix ?? '');
    final numberController = TextEditingController(text: grid[y][x]?.number ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(grid[y][x] == null ? 'Добавить контейнер' : 'Редактировать контейнер'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: prefixController,
              decoration: InputDecoration(labelText: 'Префикс (4 буквы)'),
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z]')),
              ],
            ),
            TextField(
              controller: numberController,
              decoration: InputDecoration(labelText: 'Номер (7 цифр)'),
              maxLength: 7,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
          ],
        ),
        actions: [
          if (grid[y][x] != null)
            TextButton(
              onPressed: () async {
                await DatabaseHelper().deleteContainer(widget.zone.id, x, y);
                _loadContainers();
                Navigator.pop(context);
              },
              child: Text('Удалить'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              if (prefixController.text.length == 4 &&
                  numberController.text.length == 7) {
                final container = ContainerData(
                  zoneId: widget.zone.id,
                  x: x,
                  y: y,
                  prefix: prefixController.text,
                  number: numberController.text,
                );
                if (grid[y][x] == null) {
                  await DatabaseHelper().insertContainer(container);
                } else {
                  await DatabaseHelper().updateContainer(container);
                }
                _loadContainers();
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Префикс — 4 буквы, номер — 7 цифр')),
                );
              }
            },
            child: Text(grid[y][x] == null ? 'Добавить' : 'Сохранить'),
          ),
        ],
      ),
    );
  }

  void _swapContainers(int fromX, int fromY, int toX, int toY) async {
    final fromContainer = grid[fromY][fromX];
    final toContainer = grid[toY][toX];
    setState(() {
      grid[toY][toX] = fromContainer;
      grid[fromY][fromX] = toContainer;
    });
    if (fromContainer != null) {
      await DatabaseHelper().updateContainer(ContainerData(
        zoneId: widget.zone.id,
        x: toX,
        y: toY,
        prefix: fromContainer.prefix,
        number: fromContainer.number,
      ));
    }
    if (toContainer != null) {
      await DatabaseHelper().updateContainer(ContainerData(
        zoneId: widget.zone.id,
        x: fromX,
        y: fromY,
        prefix: toContainer.prefix,
        number: toContainer.number,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Зона: ${widget.zone.name} (TKS)')),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: gridLength,
                childAspectRatio: 1,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: 4 * gridLength,
              itemBuilder: (context, index) {
                final x = index % gridLength;
                final y = index ~/ gridLength;
                return GestureDetector(
                  onDoubleTap: () => _addOrEditContainer(x, y),
                  child: LongPressDraggable(
                    delay: Duration(seconds: 3),
                    data: {'x': x, 'y': y},
                    feedback: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Color(0xFFFF6200).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          grid[y][x] == null
                              ? 'Пусто'
                              : '${grid[y][x]!.prefix}${grid[y][x]!.number}',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                    childWhenDragging: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.grey, style: BorderStyle.solid),
                      ),
                    ),
                    child: DragTarget<Map>(
                      onAccept: (data) {
                        _swapContainers(
                          data['x'] as int,
                          data['y'] as int,
                          x,
                          y,
                        );
                      },
                      builder: (context, candidateData, rejectedData) {
                        return Container(
                          decoration: BoxDecoration(
                            color: grid[y][x] == null ? Colors.white : Color(0xFFFF6200),
                            border: Border.all(
                              color: Colors.grey,
                              style: grid[y][x] == null ? BorderStyle.solid : BorderStyle.none,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              grid[y][x] == null
                                  ? 'Пусто'
                                  : '${grid[y][x]!.prefix}${grid[y][x]!.number}',
                              style: TextStyle(
                                color: grid[y][x] == null ? Colors.grey : Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  gridLength++;
                  for (var row in grid) {
                    row.add(null);
                  }
                });
              },
              child: Text('Добавить строку'),
            ),
          ),
        ],
      ),
    );
  }
}
