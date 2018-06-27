import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_paging_list/paging_list.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Flutter Paging List Demo',
      theme: new ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: new MyHomePage(title: 'Flutter Paging List'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => new _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  ExampleDataSource dataSource;

  @override
  void initState() {
    super.initState();
    dataSource = ExampleDataSource();
  }

  void refreshData() {
    dataSource.reload();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(widget.title),
      ),
      body: new PagingListView<ExampleItem, int>(
        dataSource: dataSource,
        builder: (BuildContext context, ExampleItem item) {
          return new Container(
            height: item.height,
            alignment: AlignmentDirectional.topStart,
            child: new Text(item.name),
            color: item.id.isEven ? Colors.black12 : Colors.grey,
          );
        },
      ),
      floatingActionButton: new FloatingActionButton(
        onPressed: refreshData,
        child: Icon(Icons.refresh),
      ),
    );
  }
}

class ExampleDataSource extends PagingDataSource<ExampleItem, int> {
  Duration _createDelay() => new Duration(milliseconds: new Random().nextInt(700) + 300);

  ExampleDataSource() : super(10);

  Future<List<ExampleItem>> loadBefore(ExampleItem item, int limit) {
    List<ExampleItem> page = [];
    ExampleItem prev = item != null ? item : ExampleItem(0, null);
    for (int i = 0; i < limit; i++) {
      //no data before -25
      if (prev.id > -25) {
        prev = ExampleItem(prev.id - 1, "item: ${prev.id - 1} updated: ${Random().nextInt(20)}");
        page.insert(0, prev);
      } else {
        break;
      }
    }
    return Future.delayed(_createDelay()).then((_) => Future.value(page));
  }

  Future<List<ExampleItem>> loadAfter(ExampleItem item, int limit) {
    List<ExampleItem> page = [];
    ExampleItem prev = item != null ? ExampleItem(item.id, null) : ExampleItem(-1, null);
    for (int i = 0; i < limit; i++) {
      //no data after 25
      if (prev.id < 25) {
        prev = ExampleItem(prev.id + 1, "item: ${prev.id + 1} updated: ${Random().nextInt(20)}");
        page.add(prev);
      }
    }
    return Future.delayed(_createDelay()).then((_) => Future.value(page));
  }

  @override
  int getKey(ExampleItem item) {
    return item.id;
  }
}

class ExampleItem {
  final int id;
  final String name;

  //needed only to simulate different item height
  final double _height;

  double get height => _height;

  ExampleItem(this.id, this.name) : _height = (Random().nextInt(100) + 56).toDouble();

  @override
  String toString() {
    return 'ExampleItem{name: $name}';
  }
}
