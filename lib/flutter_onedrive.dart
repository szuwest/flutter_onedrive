library flutter_onedrive;

import 'dart:convert';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onedrive/drive_item.dart';
import 'package:flutter_onedrive/onauth.dart';
import 'package:flutter_onedrive/onedrive_response.dart';
// import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' show jsonDecode;

import 'list_file_response.dart';
import 'token.dart';

class OneDrive with ChangeNotifier {
  static const String authHost = "login.microsoftonline.com";
  // static const String authEndpoint = "https://$authHost/common/oauth2/v2.0/authorize";
  static const String authEndpoint = "/common/oauth2/v2.0/authorize";
  static const String tokenEndpoint = "https://$authHost/common/oauth2/v2.0/token";
  static const String apiEndpoint = "https://graph.microsoft.com/v1.0/";
  static const String errCANCELED = "CANCELED";
  static const _appRootFolder = "special/approot";
  static const _defaultRootFolder = "root";
  static const permissionFilesReadWriteAppFolder = "Files.ReadWrite.AppFolder";
  static const permissionFilesReadWriteAll = "Files.ReadWrite.All";
  static const permissionOfflineAccess = "offline_access";

  late final ITokenManager _tokenManager;
  late final String redirectURL;
  final String scopes;
  final String clientID;
  // final String callbackSchema;
  final String state;

  OneDrive({
    required this.clientID,
    required this.redirectURL,
    this.scopes = "$permissionFilesReadWriteAll $permissionOfflineAccess",
    this.state = "OneDriveState",
    ITokenManager? tokenManager,
  }) {
    // redirectURL = "$callbackSchema://auth";
    _tokenManager = tokenManager ??
        DefaultTokenManager(
          tokenEndpoint: tokenEndpoint,
          clientID: clientID,
          redirectURL: redirectURL,
          scope: scopes,
        );
  }

  Future<bool> isConnected() async {
    final accessToken = await _tokenManager.getAccessToken();
    return (accessToken?.isNotEmpty) ?? false;
  }

  Future<bool> connect(BuildContext context) async {
// Construct the url
    // final authUrl = Uri.https(authHost, authEndpoint, {
    //   'response_type': 'code',
    //   'client_id': clientID,
    //   'redirect_uri': redirectURL,
    //   'scopes': scope,
    //   'state': state,
    // });

    try {
// construct auth uri
      final authUri = Uri.https(authHost, authEndpoint, {
        'response_type': 'code',
        'client_id': clientID,
        'redirect_uri': redirectURL,
        'scope': scopes,
        'state': state,
      });

      final callbackUrlScheme = Uri.parse(redirectURL).scheme;

// open browser and do auth
      final result = await OAuth2Helper.browserAuth(
        context: context,
        authEndpoint: authUri,
        tokenEndpoint: Uri.parse(tokenEndpoint),
        callbackUrlScheme: callbackUrlScheme,
        clientID: clientID,
        redirectURL: redirectURL,
        scopes: scopes,
      );

//  read token from Response
      if (result != null) {
        await _tokenManager.saveTokenResp(result);
        notifyListeners();
        return true;
      }
    } on PlatformException catch (err) {
      if (err.code != errCANCELED) {
        debugPrint("# OneDrive -> connect: $err");
      }
    }

    return false;
  }

  Future<void> disconnect() async {
    await _tokenManager.clearStoredToken();
    notifyListeners();
  }

  Future<OneDriveResponse> pull(String remotePath, {bool isAppFolder = true}) async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      throw Exception('No token found, please take a authentication first.');
    }

    /// We need to call this method to create app folder and make sure it exists.
    /// Otherwise, we will get "Access Denied - 403".
    /// https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder?view=odsp-graph-online
    // if (isAppFolder) {
    //   await getMetadata(remotePath, isAppFolder: isAppFolder);
    // }

    final url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}:$remotePath:/content");

    try {
      final resp = await http.get(
        url,
        headers: {"Authorization": "Bearer $accessToken"},
      );

      debugPrint("# OneDrive -> pull: ${resp.statusCode}\n# Body: ${resp.body}");

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return OneDriveResponse(
            statusCode: resp.statusCode,
            body: resp.body,
            message: "Download successfully.",
            bodyBytes: resp.bodyBytes,
            isSuccess: true);
      } else if (resp.statusCode == 404) {
        return OneDriveResponse(
            statusCode: resp.statusCode,
            body: resp.body,
            message: "File not found.",
            bodyBytes: Uint8List(0));
      } else {
        return OneDriveResponse(
            statusCode: resp.statusCode,
            body: resp.body,
            message: "Error while downloading file.",
            bodyBytes: Uint8List(0));
      }
    } catch (err) {
      debugPrint("# OneDrive -> pull: $err");
      return OneDriveResponse(message: "Unexpected exception: $err");
    }
  }

  Stream<UploadStatus> pushStream(Uint8List bytes, String remotePath, {bool isAppFolder = true}) async* {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      // No access token
      throw Exception('No token found, please take a authentication first.');
    }

    /// We need to call this method to create app folder and make sure it exists.
    /// Otherwise, we will get "Access Denied - 403".
    /// https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder?view=odsp-graph-online
    // if (isAppFolder) {
    //   await getMetadata(remotePath, isAppFolder: isAppFolder);
    // }

    const int pageSize = 1024 * 1024; // page size
    final int maxPage = (bytes.length / pageSize.toDouble()).ceil(); // total pages

// create upload session
// https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_createuploadsession?view=odsp-graph-online
    var now = DateTime.now();
    var url =
        Uri.parse("$apiEndpoint/me/drive/${_getRootFolder(isAppFolder)}:$remotePath:/createUploadSession");
    debugPrint('url = $url');
    var resp = await http.post(
      url,
      headers: {"Authorization": "Bearer $accessToken"},
    );
    debugPrint("# Create Session: ${DateTime.now().difference(now).inMilliseconds} ms");

    if (resp.statusCode == 200) {
      // create session success
      final Map<String, dynamic> respJson = jsonDecode(resp.body);
      final String uploadUrl = respJson["uploadUrl"];
      url = Uri.parse(uploadUrl);
      debugPrint('url = $url');
// use upload url to upload
      for (var pageIndex = 0; pageIndex < maxPage; pageIndex++) {
        now = DateTime.now();
        final int start = pageIndex * pageSize;
        int end = start + pageSize;
        if (end > bytes.length) {
          end = bytes.length; // cannot exceed max length
        }
        final range = "bytes $start-${end - 1}/${bytes.length}";
        final pageData = bytes.getRange(start, end).toList();
        final contentLength = pageData.length.toString();

        final headers = {
          "Authorization": "Bearer $accessToken",
          "Content-Length": contentLength,
          "Content-Range": range,
        };

        resp = await http.put(
          url,
          headers: headers,
          body: pageData,
        );

        final status = UploadStatus(pageIndex + 1, maxPage, start, end, contentLength, range);
        yield status;

        debugPrint(
            "# Upload [${pageIndex + 1}/$maxPage]: ${DateTime.now().difference(now).inMilliseconds} ms, start: $start, end: $end, contentLength: $contentLength, range: $range");

        if (resp.statusCode == 202) {
          // haven't finish, continue
          continue;
        } else if (resp.statusCode == 200 || resp.statusCode == 201) {
          // upload finished
          return;
        } else {
          // has issue
          throw Exception("Upload http error. [${resp.statusCode}]\n${resp.body}");
        }
      }
    } else {
      throw Exception("Create upload session http error [${resp.statusCode}]\n${resp.body}");
    }
  }

  Future<OneDriveResponse> push(Uint8List bytes, String remotePath, {bool isAppFolder = true}) async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      // No access token
      throw Exception('No token found, please take a authentication first.');
    }

    try {
      /// We need to call this method to create app folder and make sure it exists.
      /// Otherwise, we will get "Access Denied - 403".
      /// https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder?view=odsp-graph-online
      // if (isAppFolder) {
      //   await getMetadata(remotePath, isAppFolder: isAppFolder);
      // }

      const int pageSize = 1024 * 1024; // page size
      final int maxPage = (bytes.length / pageSize.toDouble()).ceil(); // total pages

// create upload session
// https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_createuploadsession?view=odsp-graph-online
      var now = DateTime.now();
      var url =
          Uri.parse("$apiEndpoint/me/drive/${_getRootFolder(isAppFolder)}:$remotePath:/createUploadSession");
      debugPrint('url = $url');
      var resp = await http.post(
        url,
        headers: {"Authorization": "Bearer $accessToken"},
      );
      debugPrint("# Create Session: ${DateTime.now().difference(now).inMilliseconds} ms");

      if (resp.statusCode == 200) {
        // create session success
        final Map<String, dynamic> respJson = jsonDecode(resp.body);
        final String uploadUrl = respJson["uploadUrl"];
        url = Uri.parse(uploadUrl);
        debugPrint('url = $url');
// use upload url to upload
        for (var pageIndex = 0; pageIndex < maxPage; pageIndex++) {
          now = DateTime.now();
          final int start = pageIndex * pageSize;
          int end = start + pageSize;
          if (end > bytes.length) {
            end = bytes.length; // cannot exceed max length
          }
          final range = "bytes $start-${end - 1}/${bytes.length}";
          final pageData = bytes.getRange(start, end).toList();
          final contentLength = pageData.length.toString();

          final headers = {
            "Authorization": "Bearer $accessToken",
            "Content-Length": contentLength,
            "Content-Range": range,
          };

          resp = await http.put(
            url,
            headers: headers,
            body: pageData,
          );

          debugPrint(
              "# Upload [${pageIndex + 1}/$maxPage]: ${DateTime.now().difference(now).inMilliseconds} ms, start: $start, end: $end, contentLength: $contentLength, range: $range");

          if (resp.statusCode == 202) {
            // haven't finish, continue
            continue;
          } else if (resp.statusCode == 200 || resp.statusCode == 201) {
            // upload finished
            return OneDriveResponse(
                statusCode: resp.statusCode, body: resp.body, message: "Upload finished.", isSuccess: true);
          } else {
            // has issue
            return OneDriveResponse(statusCode: resp.statusCode, body: resp.body, message: "Upload failed.");
          }
        }
      }

      debugPrint("# Upload response: ${resp.statusCode}\n# Body: ${resp.body}");
    } catch (err) {
      debugPrint("# Upload error: $err");
      return OneDriveResponse(message: "Unexpected exception: $err");
    }

    return OneDriveResponse(message: "Unexpected error.");
  }

  String _getRootFolder(bool isAppFolder) {
    return isAppFolder ? _appRootFolder : _defaultRootFolder;
  }

  Future<DriveItem> getMetadata(String remotePath, {bool isAppFolder = true}) async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      throw Exception('No token found, please take a authentication first.');
    }

    final Uri url;
    if (remotePath.isEmpty) {
      url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}");
    } else {
      url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}:$remotePath");
    }
    debugPrint('url = $url');
    final resp = await http.get(
      url,
      headers: {"Authorization": "Bearer $accessToken"},
    );
    debugPrint("# OneDrive -> metadata: path=$remotePath, ${resp.statusCode}\n# Body: ${resp.body}");
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return DriveItem.fromJson(resp.body);
    } else if (resp.statusCode == 404) {
      throw Exception("File not found.");
    }
    throw Exception("Request failed, code=${resp.statusCode}");
  }

  /// remotePath: the path of the file or folder to be listed. or empty string to list app folder.
  Future<ListFileResponse> listFiles(String remotePath, {bool isAppFolder = true}) async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      throw Exception('No token found, please take a authentication first.');
    }
    final Uri url;
    if (remotePath.isEmpty) {
      url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}/children");
    } else {
      url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}:$remotePath:/children");
    }
    debugPrint('url = $url');
    final resp = await http.get(
      url,
      headers: {"Authorization": "Bearer $accessToken"},
    );
    debugPrint("# OneDrive -> listFiles: path=$remotePath, ${resp.statusCode}\n# Body: ${resp.body}");
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return ListFileResponse.fromJson(resp.body);
    }
    throw Exception("Request failed, code=${resp.statusCode}");
  }

  Future<ListFileResponse> listAppFolderFiles() async {
    return listFiles('', isAppFolder: true);
  }

  Future<List<DriveItem>> listAllItems(String remotePath, {bool isAppFolder = true}) async {
    ListFileResponse response = await listFiles(remotePath, isAppFolder: isAppFolder);
    List<DriveItem> items = response.value ?? [];
    List<DriveItem> allItems = [];
    allItems.addAll(items);
    while(response.nextLink != null) {
      final accessToken = await _tokenManager.getAccessToken();
      try {
        final resp = await http.get(
          Uri.parse(response.nextLink!),
          headers: {"Authorization": "Bearer $accessToken"},
        );
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          response = ListFileResponse.fromJson(resp.body);
          final nextItems = response.value;
          if (nextItems != null) {
            allItems.addAll(nextItems);
          }
        } else {
          response.nextLink = null;
        }
      } catch (err) {
        debugPrint("# OneDrive -> listAllItems: $err");
        response.nextLink = null;
      }
    }
    return allItems;
  }

  Future<DriveItem> createFolder(String folderName, {String? parentPath, bool isAppFolder = true}) async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      throw Exception('No token found, please take a authentication first.');
    }
    final Uri url;
    if (parentPath == null || parentPath.isEmpty) {
      url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}/children");
    } else {
      url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}:$parentPath:/children");
    }
    debugPrint('url = $url');
    final resp = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $accessToken",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"name": folderName, "folder": {}}),
    );
    debugPrint("# OneDrive -> createFolder: parentPath=$parentPath, folderName=$folderName, ${resp.statusCode}\n# Body: ${resp.body}");
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return DriveItem.fromJson(resp.body);
    }
    throw Exception("Request failed, code=${resp.statusCode}");
  }

  Future<OneDriveResponse> deleteFile(String remotePath, {bool isAppFolder = true}) async {
    final accessToken = await _tokenManager.getAccessToken();
    if (accessToken == null) {
      throw Exception('No token found, please take a authentication first.');
    }
    final Uri url = Uri.parse("${apiEndpoint}me/drive/${_getRootFolder(isAppFolder)}:$remotePath");
    debugPrint('url = $url');
    final resp = await http.delete(
      url,
      headers: {"Authorization": "Bearer $accessToken"},
    );
    debugPrint("# OneDrive -> deleteFile: path=$remotePath, ${resp.statusCode}\n# Body: ${resp.body}");
    if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
      return OneDriveResponse(
          statusCode: resp.statusCode,
          body: resp.body,
          message: "Delete file successfully.",
          bodyBytes: null,
          isSuccess: true);
    } else if (resp.statusCode == 404) {
      return OneDriveResponse(
          statusCode: resp.statusCode,
          body: resp.body,
          message: "File not found.",
          bodyBytes: Uint8List(0));
    }
    throw Exception("Request failed, code=${resp.statusCode}");
  }
}

class UploadStatus {
  final int index;
  final int total;
  final int start;
  final int end;
  final String contentLength;
  final String range;

  UploadStatus(this.index, this.total, this.start, this.end, this.contentLength, this.range);
}
