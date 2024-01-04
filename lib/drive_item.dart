import 'dart:convert';

import 'package:flutter_onedrive/base_item.dart';

/// Created by West 0n 2023/12/21
/// Copyright @2023 WeGene

class DriveItem extends BaseItem {
  String? cTag;
  String? downloadUrl;
  List<DriveItem>? children;

  static DriveItem fromJson(String source) {
    var map = jsonDecode(source);
    return DriveItem.fromMap(map);
  }

  static DriveItem fromMap(map) {
    return DriveItem()
      ..id = map['id']
      ..createdDateTime = map['createdDateTime']
      ..lastModifiedDateTime = map['lastModifiedDateTime']
      ..name = map['name']
      ..size = map['size']
      ..eTag = map['eTag']
      ..description = map['description']
      ..webUrl = map['webUrl']
      ..downloadUrl = map['@microsoft.graph.downloadUrl']
      ..cTag = map['cTag']
      ..children = (map['children'] as List?)?.map((e) => DriveItem.fromMap(e)).cast<DriveItem>().toList();
  }
}