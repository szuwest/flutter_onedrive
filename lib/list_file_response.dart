import 'dart:convert';

import 'drive_item.dart';

/// Created by West 0n 2023/12/23
/// Copyright @2023 WeGene
class ListFileResponse {
  List<DriveItem>? value;
  String? nextLink;
  String? deltaLink;
  String? requestUrl;
  int? count;

  static ListFileResponse fromJson(String source) {
    var map = jsonDecode(source);
    return ListFileResponse.fromMap(map);
  }

  static ListFileResponse fromMap(map) {
    return ListFileResponse()
      ..value = (map['value'] as List?)?.map((e) => DriveItem.fromMap(e)).cast<DriveItem>().toList()
      ..nextLink = map['@odata.nextLink']
      ..requestUrl = map['@odata.context']
      ..count = map['@odata.count']
      ..deltaLink = map['@odata.deltaLink'];
  }
}