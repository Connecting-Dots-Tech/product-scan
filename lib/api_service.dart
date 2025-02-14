// api_service.dart

import 'package:dio/dio.dart';
import 'dart:io';

// Custom Exception Class
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException: $message ${statusCode ?? ''}';
}

// Product Model
class ProductModel {
  ProductModel({
    this.code,
    this.name,
    this.category,
    this.brand,
    this.productCode,
    this.salesPrice,
    this.bmrp,
    this.discount,
    this.barcode,
  });

  ProductModel.fromJson(dynamic json) {
    code = json['code'];
    name = json['name'];
    category = json['category'];
    brand = json['brand'];
    productCode = json['productCode'];
    // Handle different types for salesPrice
    if (json['salesPrice'] != null) {
      if (json['salesPrice'] is int) {
        salesPrice = (json['salesPrice'] as int).toDouble();
      } else if (json['salesPrice'] is double) {
        salesPrice = json['salesPrice'];
      }
    }
    if (json['bmrp'] != null) {
      if (json['bmrp'] is int) {
        bmrp = (json['bmrp'] as int).toDouble();
      } else if (json['bmrp'] is double) {
        bmrp = json['bmrp'];
      }
    }
    if (json['discount'] != null) {
      if (json['discount'] is int) {
        discount = (json['discount'] as int).toDouble();
      } else if (json['discount'] is double) {
        discount = json['discount'];
      }
    }
    barcode = json['barcode'];
  }

  String? code;
  String? name;
  String? category;
  String? brand;
  String? productCode;
  double? salesPrice;
  double? discount;
  double? bmrp;
  String? barcode;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['code'] = code;
    map['name'] = name;
    map['category'] = category;
    map['brand'] = brand;
    map['productCode'] = productCode;
    map['salesPrice'] = salesPrice;
    map['barcode'] = barcode;
    map['bmrp'] = bmrp;
    map['discount'] = discount;
    return map;
  }
}

// API Service
class ApiService {
  //static const String _baseUrl = 'http://192.168.1.11:4001';
  static const String _priceCheckerUrl =
      'https://apis.datcarts.com/price-checker';

  final Dio _dio;

  ApiService() : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'Content-Type': 'application/json',
    };
  }

  Future<List<ProductModel>> getProductByBarcode(
      String barcode, String url) async {
    try {
      print('READY TO CALL API');
      final response = await _dio.get('$url$barcode');
      print('RESPONSECODE:${response.statusCode}');
      if (response.statusCode == 200) {
        print(response.data);
        final List<dynamic> data = response.data;
        print(data);
        return data.map((json) => ProductModel.fromJson(json)).toList();
      } else {
        print('RESPONSECODE:${response.statusCode}');
        //throw ApiException('Failed to fetch products', response.statusCode);
        return [];
      }
    } on DioException catch (e) {
      throw ApiException('Network error: ${e.message}', e.response?.statusCode);
    } catch (e) {
      throw ApiException('Unexpected error: $e');
    }
  }

  Future<bool> sendPriceExtractionData({
    required File imageFile,
    required String price,
    required bool isCorrect,
    required String algorithm,
  }) async {
    try {
      print('before storing');
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(imageFile.path),
        'price': price,
        'isCorrect': isCorrect.toString(),
        'algorithm': algorithm,
      });

      final response = await _dio.post(
        _priceCheckerUrl,
        data: formData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print(response.statusMessage);
        return true;
      } else {
        print(response.statusMessage);
      }

      throw ApiException('Upload failed', response.statusCode);
    } on DioException catch (e) {
      throw ApiException('Network error: ${e.message}', e.response?.statusCode);
    } catch (e) {
      throw ApiException('Unexpected error: $e');
    }
  }
}
