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
class Product {
  final String code;
  final String name;
  final String category;
  final String brand;
  final String productCode;
  final String bmrp;
  final String barcode;
  final String discount;

  final String salesPrice;

  const Product({
    required this.code,
    required this.name,
    required this.category,
    required this.brand,
    required this.productCode,
    required this.bmrp,
    required this.barcode,
    required this.discount,
    required this.salesPrice,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      productCode: json['productCode']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      bmrp: json['bmrp']?.toString() ?? '',
      discount: json['discount']?.toString() ?? '',
      salesPrice: json['saleprice']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'category': category,
        'brand': brand,
        'productCode': productCode,
        'barcode': barcode,
        'bmrp': bmrp,
        'discount': discount,
        'saleprice': salesPrice,
      };
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

  Future<List<Product>> getProductByBarcode(String barcode) async {
    try {
      print('READY TO CALL API');
      final response =
          await _dio.get('http://192.168.1.2:4001/products/barcode/$barcode');
      print('RESPONSECODE:${response.statusCode}');
      if (response.statusCode == 200) {
        print(response.data);
        final List<dynamic> data = response.data;
        print(data);
        return data.map((json) => Product.fromJson(json)).toList();
      }

      throw ApiException('Failed to fetch products', response.statusCode);
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
