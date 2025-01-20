import 'package:http/http.dart' as http;
import 'dart:io';

import 'package:http/http.dart';

class PriceExtractionApiService {
  Future<String> sendDataToAPI({
    required File imageFile,
    required String price,
    required bool isCorrect,
    required String algorithm,
  }) async {
    print('$imageFile,$price,$isCorrect,$algorithm');
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://apis.datcarts.com/price-checker'),
      );
      MultipartFile multipartFile = await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      );

      // Add text fields
      request.fields['price'] = price;
      request.fields['isCorrect'] = isCorrect.toString();
      request.fields['algorithm'] = algorithm;

      // Add the raw image file
      request.files.add(multipartFile
          // http.MultipartFile.fromPath('image', imageFile.path
          //     // imageFile.readAsBytes().asStream(),
          //     // imageFile.lengthSync(),
          //     // filename: imageFile.path.split('/').last,
          //     ),
          );

      // Send the request
      var requestData = await request.send();
      var response = await http.Response.fromStream(requestData);

      // Handle response
      if (response.statusCode == 200) {
        print('Upload successful');
        return 'Success';
      } else {
        print('Upload failed: ${response.statusCode}:${response.body}');
        return 'Failure';
      }
    } catch (e) {
      print('Error uploading file: $e');
      return 'Failure';
    }
  }
}
