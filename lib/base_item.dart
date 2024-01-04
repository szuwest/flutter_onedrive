import 'dart:convert';

/// Created by West 0n 2023/12/18
/// Copyright @2023 WeGene
///{
//   "id": "string (identifier)",
//   "createdBy": { "@odata.type": "microsoft.graph.identitySet" },
//   "createdDateTime": "datetime",
//   "description": "string",
//   "eTag": "string",
//   "lastModifiedBy": { "@odata.type": "microsoft.graph.identitySet" },
//   "lastModifiedDateTime": "datetime",
//   "name": "string",
//   "parentReference": { "@odata.type": "microsoft.graph.itemReference" },
//   "webUrl": "url"
// }
class BaseItem {
  String? id;
  String? createdDateTime;
  String? lastModifiedDateTime;
  String? name;
  int? size;
  String? webUrl;
  String? eTag;
  String? description;

  static BaseItem fromJson(String source) {
    var map = jsonDecode(source);
    return BaseItem.fromMap(map);
  }

  static BaseItem fromMap(map) {
    return BaseItem()
      ..id = map['id']
      ..createdDateTime = map['createdDateTime']
      ..lastModifiedDateTime = map['lastModifiedDateTime']
      ..name = map['name']
      ..size = map['size']
      ..eTag = map['eTag']
      ..description = map['description']
      ..webUrl = map['webUrl'];
  }
}