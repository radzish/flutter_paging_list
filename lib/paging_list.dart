library flutter_paging_list;

import 'dart:async';
import 'dart:io';
import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

typedef PagingItemBuilder<T> = Widget Function(BuildContext, T);

//TODO: BUG initial loading when list is offstage: initial has before and after, but after has not enough height => should do another call
//TODO: refactor build method

class PagingListView<T, K> extends StatefulWidget {
  final PagingDataSource<T, K> dataSource;
  final PagingItemBuilder<T> builder;
  final bool reverse;

  PagingListView({
    @required this.dataSource,
    @required this.builder,
    this.reverse = false,
  });

  @override
  _PagingListViewState<T, K> createState() {
    return new _PagingListViewState<T, K>();
  }
}

class _PagingListViewState<T, K> extends State<PagingListView<T, K>> {
  static const _loading_indicator_height = 56.0;

  PagingDataSource<T, K> _dataSource;

  List<T> _oldData;
  List<T> _data;

  ScrollController _controller;
  ScrollController _oldController;

  bool _initialLoading = false;

  bool _firstFrameAfterBuild;

  bool _initialScrollRequested = false;
  bool _loadBeforeRequested = false;
  bool _loadAfterRequested = false;


////

  _ItemViewport<T> _firstVisibleItemViewport;
  _ItemViewport<T> _firstCompletelyVisibleItemViewport;

  double _firstCompletelyVisibleItemRelativeOffset;

  Map<K, _ItemViewport<T>> _oldViewports;
  Map<K, _ItemViewport<T>> _itemViewports = LinkedHashMap();

  void _prependItemViewports() {
    RenderBox dataToPrependBox =
    _dataToPrependOffstageKey.currentContext?.findRenderObject() as RenderBox;

    Map<K, _ItemViewport<T>> _itemViewportsOld = _itemViewports;

    _itemViewports = LinkedHashMap();

    int i = 0;
    double position = _hasDataBefore ? _loading_indicator_height + double.minPositive : 0.0;

    _ItemViewport<T> prevViewport;

    dataToPrependBox.visitChildren((renderObject) {
      RenderBox child = renderObject;
      T item = _dataToPrepend[i++];
      K key = _dataSource.getKey(item);
      double height = child.size.height;
      _ItemViewport viewport = _ItemViewport<T>(item, position, height);
      _itemViewports[key] = viewport;

      if (_firstVisibleItemViewport != null) {
        K currentFirstVisibleItemKey = _dataSource.getKey(_firstVisibleItemViewport.item);
        if (key == currentFirstVisibleItemKey) {
          _firstVisibleItemViewport = viewport;
        }
      }

      if (_firstCompletelyVisibleItemViewport != null) {
        K currentFirstCompletelyVisibleItemKey = _dataSource.getKey(
            _firstCompletelyVisibleItemViewport.item);
        if (key == currentFirstCompletelyVisibleItemKey) {
          _firstCompletelyVisibleItemViewport = viewport;
        }
      }


      prevViewport = viewport;
      position += height + double.minPositive;
    });

    _itemViewportsOld.values.forEach((itemViewport) {
      itemViewport.position = position;
      position += itemViewport.height + double.minPositive;
    });

    _itemViewports.addAll(_itemViewportsOld);
  }

  void _appendItemViewports() {
    RenderBox dataToAppendBox =
    _dataToAppendOffstageKey.currentContext?.findRenderObject() as RenderBox;

    int i = 0;
    _ItemViewport lastItem = _itemViewports.values.isNotEmpty ? _itemViewports.values.last : null;
    double position = lastItem != null ? lastItem.position + lastItem.height +
        double.minPositive : 0.0;

    _ItemViewport<T> prevViewport;

    dataToAppendBox.visitChildren((renderObject) {
      RenderBox child = renderObject;
      T item = _dataToAppend[i++];
      K key = _dataSource.getKey(item);
      double height = child.size.height;
      _ItemViewport viewport = _ItemViewport<T>(item, position, height);
      _itemViewports[key] = viewport;

      if (_firstVisibleItemViewport != null) {
        K currentFirstVisibleItemKey = _dataSource.getKey(_firstVisibleItemViewport.item);
        if (key == currentFirstVisibleItemKey) {
          _firstVisibleItemViewport = viewport;
        }
      }

      if (_firstCompletelyVisibleItemViewport != null) {
        K currentFirstCompletelyVisibleItemKey = _dataSource.getKey(
            _firstCompletelyVisibleItemViewport.item);
        if (key == currentFirstCompletelyVisibleItemKey) {
          _firstCompletelyVisibleItemViewport = viewport;
        }
      }

      prevViewport = viewport;
      position += height + double.minPositive;
    });
  }

  void _updateFirstVisibleItemViewports(double offset) {
    //TODO: currently it looks from the beginning all the time as POC.
    //Need to improve this
    //IDEA: remember last item offset, compare to current one so you know when to search to:
    //forward or backward relatively to prev item
    _ItemViewport prevItemViewport;
    for (Iterator<_ItemViewport> it = _itemViewports.values.iterator; it.moveNext();) {
      _ItemViewport itemViewport = it.current;
      if (offset == itemViewport.position) {
        _firstVisibleItemViewport = itemViewport;
        _firstCompletelyVisibleItemViewport = itemViewport;
        break;
      } else if (itemViewport.position > offset) {
        _firstVisibleItemViewport = prevItemViewport ?? _firstCompletelyVisibleItemViewport;
        _firstCompletelyVisibleItemViewport = itemViewport;
        break;
      }
      prevItemViewport = itemViewport;
    }

    _firstCompletelyVisibleItemRelativeOffset =
        _firstCompletelyVisibleItemViewport.position - offset;

    print(
        "FVI/FCVI: ${_firstVisibleItemViewport.item}/${_firstCompletelyVisibleItemViewport
            .item}/FCVI offset:${_firstCompletelyVisibleItemViewport.position}/offset:${offset}");
  }

//////

  GlobalObjectKey _dataToPrependOffstageKey = new GlobalObjectKey("_dataToPrependOffstageKey");
  GlobalObjectKey _dataToAppendOffstageKey = new GlobalObjectKey("_dataOffstageKey");

  GlobalObjectKey _listContainerKey = new GlobalObjectKey("_listContainerKey");

  bool _hasDataBefore = false;
  bool _hasDataAfter = false;

  bool _loadBeforeInProgress = false;
  bool _loadAfterInProgress = false;

  List<T> _dataToPrepend = [];
  List<T> _dataToAppend = [];

  double _totalHeight = 0.0;

  _PagingListViewState() {}

  @override
  void didUpdateWidget(PagingListView<T, K> oldWidget) {
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
    Future.microtask(() {
      _createBindingCallback();
    });
  }

  void _createBindingCallback() {
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (_firstFrameAfterBuild) {
        _firstFrameAfterBuild = false;

        if (_initialScrollRequested || _loadBeforeRequested || _loadAfterRequested) {
          RenderBox dataToPrependBox =
          _dataToPrependOffstageKey.currentContext?.findRenderObject() as RenderBox;
          RenderBox dataToAppendBox =
          _dataToAppendOffstageKey.currentContext?.findRenderObject() as RenderBox;

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


            ////

            if (_initialScrollRequested || _loadBeforeRequested) {
              _prependItemViewports();
            }

            if (_initialScrollRequested || _loadAfterRequested) {
              _appendItemViewports();
            }

            ////


            //we need to restore prev scoll position after data refresh
            if (_initialScrollRequested && _firstCompletelyVisibleItemViewport != null) {
              double offset = _firstCompletelyVisibleItemViewport.position -
                  _firstCompletelyVisibleItemRelativeOffset;
              if (_controller == null) {
                _controller = _createController(offset);
              } else {
                _controller.jumpTo(offset);
              }
              _updateFirstVisibleItemViewports(offset);
            } else
              //we need to manage scroll position only when data is prepended (or on initial load)
            if (_initialScrollRequested || _loadBeforeRequested) {
              double offset;
              if (_controller == null) {
                offset = dataToPrependBox.size.height +
                    (_hasDataBefore ? _loading_indicator_height : 0);
                _controller = _createController(offset);
              } else {
                offset = dataToPrependBox.size.height +
                    _controller.offset -
                    (!_hasDataBefore ? _loading_indicator_height : 0);
                _controller.jumpTo(offset);
              }
              _updateFirstVisibleItemViewports(offset);
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

            _checkIfLoadingNeeded();
          });
        }

        _checkIfLoadingNeeded();
      }
    });
  }

  ScrollController _createController(double offset) =>
      new ScrollController(
        initialScrollOffset: offset,
        keepScrollOffset: false,
      )
        ..addListener(_scrollHandler);

  @override
  Widget build(BuildContext context) {
    _log("build");
    _firstFrameAfterBuild = true;

    List<Widget> children = [];

    List<T> dataToShow = _data;

    if (dataToShow.isNotEmpty) {
      List<Widget> items = dataToShow.map((item) => _itemBuilder(context, item)).toList();

      if (_hasDataBefore) {
        items.insert(0, _createLoadingIndicator());
      }
      if (_hasDataAfter) {
        items.add(_createLoadingIndicator());
      }

      Widget listView = new ListView(
        reverse: widget.reverse,
        controller: _controller,
        children: items,
      );

      children.add(new Stack(
        key: _listContainerKey,
        fit: StackFit.expand,
        children: <Widget>[
          listView,
        ],
      ));
    } else {
      ///////

      //TODO: refactor by merging with code above

      if (_oldData != null && _oldData.isNotEmpty) {
        print("old data build");

        List<Widget> items = _oldData.map((item) => _itemBuilder(context, item)).toList();

        if (_hasDataBefore) {
          items.insert(0, _createLoadingIndicator());
        }
        if (_hasDataAfter) {
          items.add(_createLoadingIndicator());
        }

        print("old data old controller offset: ${_oldController.offset}");

        Widget listView = new ListView(
          reverse: widget.reverse,
          controller: ScrollController(initialScrollOffset: _oldController.offset),
          children: items,
        );

        children.add(new Stack(
          fit: StackFit.expand,
          children: <Widget>[
            listView,
          ],
        ));
      }


      ///////


    }

    if (_initialScrollRequested || _loadBeforeRequested || _loadAfterRequested) {
      double width = MediaQuery
          .of(context)
          .size
          .width;

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

    if (_initialLoading) {
      children.add(new LinearProgressIndicator());
    }

    return new Stack(
      children: children,
    );
  }

  void _reload() {
    _log("invalidate");
    _dataSource = widget.dataSource;
    _oldViewports = _itemViewports;
    _itemViewports = LinkedHashMap();
    _dataToPrepend = [];
    _dataToAppend = [];
    _totalHeight = 0.0;
    _loadInitial();
  }

  void _invalidate() {
    _log("invalidate");
    _dataSource = widget.dataSource;
    _dataSource._reloadStreamBuilder.stream.listen((_) => _reload());
    _data = [];
    _firstVisibleItemViewport = null;
    _firstCompletelyVisibleItemViewport = null;
    _oldViewports = LinkedHashMap();
    _itemViewports = LinkedHashMap();
    _controller = null;
    _dataToPrepend = [];
    _dataToAppend = [];
    _totalHeight = 0.0;
    _hasDataBefore = false;
    _hasDataAfter = false;
    _loadInitial();
  }

  Widget _itemBuilder(BuildContext context, T item) {
    return Container(
      key: ValueKey<K>(_dataSource.getKey(item)),
      child: widget.builder(context, item),
    );
  }

  void _loadInitial() async {
    setState(() {
      _initialLoading = true;
    });

//    improve loading when we are at the beginning of the list
//    think what should we do if we have 1 item in the list only (maybe request everything ???)

    T requestItemBefore;
    T requestItemAfter;

    //if we have only 1 item, we will re-request everything
    if (_oldViewports.length > 1) {
      //calculating prev/next item:
      //TODO: looking from beginning, need to optimize it somehow
      _ItemViewport<T> prevItem;
      _ItemViewport<T> nextItem;

      for (Iterator<_ItemViewport<T>> it = _oldViewports.values.iterator; it.moveNext();) {
        _ItemViewport<T> current = it.current;
        if (current.item == _firstCompletelyVisibleItemViewport.item) {
          if (it.moveNext()) {
            nextItem = it.current;
          }
          break;
        }
        prevItem = current;
      }

      if (prevItem == null) {
        //case when we are positioned on the top
        requestItemBefore = nextItem.item;
        requestItemAfter = _firstCompletelyVisibleItemViewport.item;
      } else {
        //case when we are positioned in the middle
        requestItemBefore = _firstCompletelyVisibleItemViewport.item;
        requestItemAfter = prevItem.item;
      }
    }

    Future<List<T>> beforeFuture = _dataSource.loadBefore(requestItemBefore, _dataSource.pageSize);
    Future<List<T>> afterFuture = _dataSource.loadAfter(requestItemAfter, _dataSource.pageSize);
    List<List<T>> results = await Future.wait([beforeFuture, afterFuture]);

    setState(() {
      _oldData = _data;
      _data = [];

      _oldController = _controller;
      _controller = null;

      _hasDataBefore = false;
      _hasDataAfter = false;

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
      child: Platform.isIOS
          ? new CupertinoActivityIndicator(radius: 16.0)
          : new CircularProgressIndicator(),
      height: _loading_indicator_height,
    );
  }

  void _scrollHandler() {
    _updateFirstVisibleItemViewports(_controller.offset);
    _checkIfLoadingNeeded();

    print("FCVIO ${_firstCompletelyVisibleItemRelativeOffset}");
  }

  void _checkIfLoadingNeeded() {
    RenderBox container = _listContainerKey.currentContext?.findRenderObject() as RenderBox;
    if (container != null) {
      double containerHeight = container.size.height;
      if (_totalHeight < containerHeight) {
        _requestLoadAfter();
      } else {
        if (_controller != null && _controller.hasClients) {
          if (_controller.offset < _loading_indicator_height) {
            _requestLoadBefore();
          } else {
            if (_controller.offset >
                _totalHeight - containerHeight + (_hasDataBefore ? _loading_indicator_height : 0)) {
              _requestLoadAfter();
            }
          }
        }
      }
    }
  }

  void _requestLoadAfter() {
    if (!_initialLoading && !_loadAfterInProgress && _hasDataAfter) {
      _log("load after requested");
      _loadAfterInProgress = true;
      _loadAfter();
    }
  }

  void _requestLoadBefore() {
    if (!_initialLoading && !_loadBeforeInProgress && _hasDataBefore) {
      _log("load before requested");
      _loadBeforeInProgress = true;
      _loadBefore();
    }
  }

  void _loadBefore() async {
    List<T> dataBefore =
    await _dataSource.loadBefore(_data.isNotEmpty ? _data[0] : null, _dataSource.pageSize);
    setState(() {
      _dataToPrepend = dataBefore;
      _loadBeforeRequested = true;
    });
  }

  void _loadAfter() async {
    List<T> dataAfter =
    await _dataSource.loadAfter(_data.isNotEmpty ? _data.last : null, _dataSource.pageSize);
    setState(() {
      _dataToAppend = dataAfter;
      _loadAfterRequested = true;
    });
  }

}

abstract class PagingDataSource<T, K> {
  final int pageSize;

  StreamController<Null> _reloadStreamBuilder = StreamController();

  PagingDataSource(this.pageSize);

  Future<List<T>> loadBefore(T item, int limit) {
    return Future.value([]);
  }

  Future<List<T>> loadAfter(T item, int limit) {
    return Future.value([]);
  }

  K getKey(T item);

  void reload() {
    _reloadStreamBuilder.add(null);
  }

}

_log(String message) {
  print("flutter_paging_list: $message");
}

class _ItemViewport<T> {
  T item;
  double position;
  double height;

  _ItemViewport(this.item, this.position, this.height);
}