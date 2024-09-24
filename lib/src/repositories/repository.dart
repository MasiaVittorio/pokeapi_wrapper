import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sid_base/sid_base.dart';

import '../../pokeapi_wrapper.dart';
import '../repositories.dart';

class Repository implements IRepository {
  @override
  Future<Either<Error, String?>> get(String url) async {
    String? localStorageValue = await _getFromLocalStorage(url);
    if (localStorageValue != null) {
      return Right(localStorageValue);
    }

    Either<Error, String?> apiStorageValue = await _getFromApi(url);
    if (apiStorageValue.isRight) {
      String? value = apiStorageValue.right;
      if (value != null) {
        await _putToLocalStorage(url, value);
      }
      return Right(value);
    }
    return apiStorageValue;
  }

  Future<List<String>> get _cacheKeys async {
    return [
      for (final key in await _getPersistence.getKeys())
        if (key case String keyString)
          // if(keyString.startsWith("http")) // all keys belong to only this cache
          keyString,
    ];
  }

  @override
  Future<int> clearCache(Function(String key, int progress) onProgress) async {
    int sizeTotal = 0;
    List<String> keys = await _cacheKeys;
    for (int i = 0; i < keys.length; i++) {
      String key = keys.elementAt(i);
      sizeTotal += (await _getPersistence.readEncodedObject(key))?.length ?? 0;
      await (await _getPersistence.remove(key));
      onProgress(key, (i + 1) * 100 ~/ keys.length);
    }
    return sizeTotal;
  }

  @override
  Future<int> get cacheSize async {
    int sizeTotal = 0;
    List<String> keys = await _cacheKeys;
    for (int i = 0; i < keys.length; i++) {
      String key = keys.elementAt(i);
      sizeTotal += (await (_getPersistence).readEncodedObject(key))?.length ?? 0;
    }
    return sizeTotal;
  }

  /// local storage

  HivePersistence? _hivePersistence;
  PersistenceProvider get _getPersistence {
    _hivePersistence ??= HivePersistence(boxName: "poke-api-wrapper-cache");
    return _hivePersistence!;
  }

  Future<String?> _getFromLocalStorage(String url) async {
    final String? value = (await _getPersistence.readEncodedObject(url));
    return value;
  }

  Future<bool> _putToLocalStorage(String url, String value) async {
    await (await _getPersistence.write(url, value));
    return true;
  }

  /// api

  Future<Either<Error, String?>> _getFromApi(String url) async {
    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        // print("_getFromApi OK ($url)");
        return Right(response.body);
      } else {
        // print("_getFromApi Error ($url) => ${response.statusCode} - ${response.body}");
        return Left(StateError(response.body));
      }
    } catch (e) {
      // print("_getFromApi Error ($url) => ${e.toString()}");
      return Left(StateError(e.toString()));
    }
  }

  @override
  Future<Either<Error, Uint8List>> getContent(String url) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? value = prefs.getString(url);
      if (value != null) return Right(Uint8List.fromList(value.codeUnits));
      var response = await http.get(Uri.parse(url));
      Uint8List bytes = response.bodyBytes;
      final String downloadContent = String.fromCharCodes(bytes);
      await prefs.setString(url, downloadContent);
      return Right(bytes);
    } catch (e) {
      return Left(StateError(e.toString()));
    }
  }
}
