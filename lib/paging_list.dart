library flutter_paging_list;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

typedef PagingItemBuilder<T> = Widget Function(BuildContext, T);

class PagingListView<T> extends StatefulWidget {
  final PagingDataSource<T> dataSource;
  final PagingItemBuilder<T> builder;
  final bool reverse;

  PagingListView({
    @required this.dataSource,
    @required this.builder,
    this.reverse = false,
  });

  @override
  PagingListViewState<T> createState() {
    return new PagingListViewState<T>();
  }
}

class PagingListViewState<T> extends State<PagingListView<T>> {
  static const _loading_indicator_height = 56.0;

  PagingDataSource<T> _dataSource;

  List<T> _data;

  ScrollController _controller;

  bool _initialLoading = false;

  bool _firstFrameAfterBuild;

  bool _initialScrollRequested = false;
  bool _loadBeforeRequested = false;
  bool _loadAfterRequested = false;

  GlobalObjectKey _dataToPrependOffstageKey =
      new GlobalObjectKey("_dataToPrependOffstageKey");
  GlobalObjectKey _dataToAppendOffstageKey =
      new GlobalObjectKey("_dataOffstageKey");

  GlobalObjectKey _listContainerKey = new GlobalObjectKey("_listContainerKey");

  bool _hasDataBefore = false;
  bool _hasDataAfter = false;

  bool _loadBeforeInProgress = false;
  bool _loadAfterInProgress = false;

  List<T> _dataToPrepend;
  List<T> _dataToAppend = [];

  double _totalHeight = 0.0;

  @override
  void didUpdateWidget(PagingListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dataSource == null ||
        !identical(widget.dataSource, oldWidget.dataSource) ||
        !identical(widget.builder, oldWidget.builder)) {
      _invalidate();
    }
  }

  @override
  void initState() {
    super.initState();
    _invalidate();

    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (_firstFrameAfterBuild) {
        _firstFrameAfterBuild = false;

        if (_initialScrollRequested ||
            _loadBeforeRequested ||
            _loadAfterRequested) {
          RenderBox dataToPrependBox = _dataToPrependOffstageKey.currentContext
              ?.findRenderObject() as RenderBox;
          RenderBox dataToAppendBox = _dataToAppendOffstageKey.currentContext
              ?.findRenderObject() as RenderBox;

          setState(() {
            if (_initialScrollRequested || _loadBeforeRequested) {
              _data.insertAll(0, _dataToPrepend);
              _totalHeight += dataToPrependBox.size.height;
              _hasDataBefore = _dataToPrepend.length >= _dataSource.pageSize;
            }
            if (_initialScrollRequested || _loadAfterRequested) {
              _data.addAll(_dataToAppend);
              _totalHeight += dataToAppendBox.size.height;
              _hasDataAfter = _dataToAppend.length >= _dataSource.pageSize;
            }

            //we need to manage scroll position only when data is prepended (or on initial load)
            if (_initialScrollRequested || _loadBeforeRequested) {
              if (_controller == null) {
                _controller = _createController(dataToPrependBox.size.height +
                    (_hasDataBefore ? _loading_indicator_height : 0));
              } else {
                _controller.jumpTo(dataToPrependBox.size.height +
                    _controller.offset -
                    (!_hasDataBefore ? _loading_indicator_height : 0));
              }
            }

            if (_initialScrollRequested) {
              _initialScrollRequested = false;
            }
            if (_loadBeforeRequested) {
              _loadBeforeRequested = false;
            }
            if (_loadAfterRequested) {
              _loadAfterRequested = false;
            }

            _initialLoading = false;
            _loadBeforeInProgress = false;
            _loadAfterInProgress = false;
          });
        }
      }
    });
  }

  ScrollController _createController(double height) => new ScrollController(
        initialScrollOffset: height,
        keepScrollOffset: false,
      )..addListener(_scrollListener);

  @override
  Widget build(BuildContext context) {
    _firstFrameAfterBuild = true;

    List<Widget> children = [];
    if (_initialLoading) {
      children.add(new LinearProgressIndicator());
    }

    if (!_initialScrollRequested) {
      List<Widget> items =
          _data.map((item) => _itemBuilder(context, item)).toList();

      if (_hasDataBefore) {
        items.insert(0, _createLoadingIndicator());
      }
      if (_hasDataAfter) {
        items.add(_createLoadingIndicator());
      }

      Widget listView = new GestureDetector(
        child: new ListView(
          reverse: widget.reverse,
          controller: _controller,
          children: items,
        ),
      );

      children.add(listView);
    }

    if (_initialScrollRequested ||
        _loadBeforeRequested ||
        _loadAfterRequested) {
      double width = MediaQuery.of(context).size.width;

      List<Positioned> positionedChildren = <Positioned>[];

      if (_initialScrollRequested || _loadBeforeRequested) {
        List<Widget> dataToPrependOffstageItems =
            _dataToPrepend.map((item) => _itemBuilder(context, item)).toList();
        positionedChildren.add(
          new Positioned(
            left: 0.0,
            top: 0.0,
            width: width,
            child: new Column(
              key: _dataToPrependOffstageKey,
              children: dataToPrependOffstageItems,
            ),
          ),
        );
      }

      if (_initialScrollRequested || _loadAfterRequested) {
        List<Widget> dataToAppendOffstageItems =
            _dataToAppend.map((item) => _itemBuilder(context, item)).toList();
        positionedChildren.add(
          new Positioned(
            left: 0.0,
            top: 0.0,
            width: width,
            child: new Column(
              key: _dataToAppendOffstageKey,
              children: dataToAppendOffstageItems,
            ),
          ),
        );
      }

      Offstage offstage = new Offstage(
        offstage: true,
        child: new Stack(
          children: positionedChildren,
        ),
      );

      children.add(offstage);
    }

    return new Stack(
      key: _listContainerKey,
      children: children,
    );
  }

  void _invalidate() {
    _dataSource = widget.dataSource;
    _data = [];
    _loadInitial();
  }

  Widget _itemBuilder(BuildContext context, T item) {
    return widget.builder(context, item);
  }

  void _loadInitial() async {
    setState(() {
      _initialLoading = true;
    });
    Future<List<T>> beforeFuture =
        _dataSource.loadBefore(null, _dataSource.pageSize);
    Future<List<T>> afterFuture =
        _dataSource.loadAfter(null, _dataSource.pageSize);
    List<List<T>> results = await Future.wait([beforeFuture, afterFuture]);
    setState(() {
      List<T> dataBefore = results[0];
      List<T> dataAfter = results[1];

      _dataToPrepend = dataBefore;
      _dataToAppend = dataAfter;

      _hasDataBefore = dataBefore.length >= _dataSource.pageSize;
      _hasDataAfter = dataAfter.length >= _dataSource.pageSize;

      _initialScrollRequested = true;
    });
  }

  Widget _createLoadingIndicator() {
    return new Container(
      alignment: AlignmentDirectional.center,
      child: new CircularProgressIndicator(),
      height: _loading_indicator_height,
    );
  }

  void _scrollListener() {
    if (_controller.offset < _loading_indicator_height) {
      if (!_loadBeforeInProgress && _hasDataBefore) {
        _loadBeforeInProgress = true;
        _loadBefore();
      }
    } else {
      RenderBox _listContainerBox =
          _listContainerKey.currentContext?.findRenderObject() as RenderBox;
      if (_controller.offset >
          _totalHeight -
              _listContainerBox.size.height +
              (_hasDataBefore ? _loading_indicator_height : 0)) {
        if (!_loadAfterInProgress && _hasDataAfter) {
          _loadAfterInProgress = true;
          _loadAfter();
        }
      }
    }
  }

  void _loadBefore() async {
    print("!!!!!!!!!!!!!!!!!! load before ...");
    List<T> dataBefore = await _dataSource.loadBefore(
        _data.isNotEmpty ? _data[0] : null, _dataSource.pageSize);
    setState(() {
      _dataToPrepend = dataBefore;
      _loadBeforeRequested = true;
    });
  }

  void _loadAfter() async {
    print("!!!!!!!!!!!!!!!!!! load after ...");
    List<T> dataAfter = await _dataSource.loadAfter(
        _data.isNotEmpty ? _data.last : null, _dataSource.pageSize);
    setState(() {
      _dataToAppend = dataAfter;
      _loadAfterRequested = true;
    });
  }
}

abstract class PagingDataSource<T> {
  final int pageSize;

  PagingDataSource(this.pageSize);

  Future<List<T>> loadBefore(T item, int limit) {
    return Future.value([]);
  }

  Future<List<T>> loadAfter(T item, int limit) {
    return Future.value([]);
  }
}
