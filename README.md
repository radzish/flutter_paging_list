# flutter_paging_list

Paging List Library for Flutter.
List that lazily loads more data when scrolled to first/last item.

## Usage

### Define Data Source
```dart
class ExampleDataSource extends PagingDataSource<ExampleItem> {

  ExampleDataSource() : super(10 /*page size*/);

  Future<List<ExampleItem>> loadBefore(ExampleItem item, int limit) {
    //return data before that goes before item; initially item will always be null
  }

  Future<List<ExampleItem>> loadAfter(ExampleItem item, int limit) {
    //return data that goes after item; initially item will always be null
  }
  
}
```

### Initialize Data Source:
```dart
  @override
  void initState() {
    super.initState();
    dataSource = ExampleDataSource();
  }
```

### Build List
```dart
  Widget build(BuildContext context) {
    return new PagingListView<ExampleItem>(
      dataSource: dataSource,
      builder: (BuildContext context, ExampleItem item) {
         //create and return widget for corresponding item
      },
    );
  }
```