import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:price_snap/pricechecker_api_service.dart';
import 'package:price_snap/product_details_page.dart';
import 'price_extraction_service.dart';

class PriceExtractorNERApp extends StatefulWidget {
  const PriceExtractorNERApp({super.key});

  @override
  _PriceExtractorNERAppState createState() => _PriceExtractorNERAppState();
}

class _PriceExtractorNERAppState extends State<PriceExtractorNERApp> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer();
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  late EntityExtractor _entityExtractor;
  final PriceExtractionService _priceExtractionService =
      PriceExtractionService();
  final ApiService _apiService = ApiService();
  TextEditingController _priceController = TextEditingController();

  String _barcode = '';

  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isPaused = false;

  bool _isScanning = false;

  bool _isAPIcomplete = true;
  bool _isBarcodeScanner = false;

  File? imageFile; // Placeholder for image file
  String? price; // TextField value
  bool isCorrect = true; // Flag for correctness
  String algorithm = ''; // Algorithm name ('NER' or 'regEX')

  Product? resulProduct;

  List<Product> sample = [
    Product(
        code: '1',
        name: 'Book',
        category: 'stationary',
        brand: 'Paperage',
        productCode: '12345',
        salesPrice: '56',
        barcode: '8906150411104'),
    Product(
        code: '2',
        name: 'Biscuit',
        category: 'food',
        brand: 'Sunfiest',
        productCode: '345',
        salesPrice: '55',
        barcode: '8906150411104'),
    // Product(
    //     code: '3',
    //     name: 'Pen',
    //     category: 'stationary',
    //     brand: 'cello',
    //     productCode: '543',
    //     salesPrice: '10.00',
    //     barcode: '8902102127468')
  ];
  Future<void> scanProduct() async {
    Product? product = await productDetails(); // Call the function

    if (mounted) {
      setState(() {
        resulProduct = product; // Store result and update UI
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    //WidgetsBinding.instance.addObserver(this);
    _entityExtractor =
        EntityExtractor(language: EntityExtractorLanguage.english);
    _priceController.addListener(() {
      setState(() {
        // Trigger UI updates whenever the text changes
      });
    });
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      setState(() {
        _isCameraInitialized = true;
      });
      _startScanning();
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  Future<void> _startScanning() async {
    if (_cameraController == null || _isScanning) return;

    setState(() {
      _isScanning = true;
    });

    Product? product = await productDetails(); // Scan for a product

    if (product != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailsPage(product: product),
        ),
      ).then((_) {
        _startScanning();
      });
    }

    setState(() {
      _isScanning = false;
    });
  }

//BARCODE SCANNER
  Future<String?> _startBarcodeScanning(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final InputImage inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _getCameraRotation(),
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    try {
      final List<Barcode> barcodes =
          await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        return barcodes.first.displayValue;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Barcode scanning error: $e');
      }
    }

    return null;
  }

  InputImageRotation _getCameraRotation() {
    final deviceRotation = _cameraController!.description.sensorOrientation;
    if (deviceRotation == 90) return InputImageRotation.rotation90deg;
    if (deviceRotation == 180) return InputImageRotation.rotation180deg;
    if (deviceRotation == 270) return InputImageRotation.rotation270deg;
    return InputImageRotation.rotation0deg;
  }

  Future<String?> _processImageForPriceExtraction(CameraImage image) async {
    try {
      // Convert CameraImage to InputImage
      final inputImage = _convertCameraImageToInputImage(image);

      // Recognize text from the image
      final recognizedText = await _textRecognizer.processImage(inputImage);
      print("Recognized Text: ${recognizedText.text}");

      // Define price-related keywords
      final List<String> priceKeywords = [
        'Rs',
        'M.R.P',
        'Maximum Retail Price',
        '₹',
        'rp',
        'MRP',
        'Rupees',
        'Price'
      ];

      // Extract and combine text with keywords
      String combinedText = _priceExtractionService.extractCombinedText(
          recognizedText.blocks, priceKeywords);
      print("Combined Text before preprocessing: $combinedText");

      // Skip further processing if no text was combined
      if (combinedText.isEmpty) {
        return null;
      }

      // Preprocess the combined text
      String preprocessedText = _priceExtractionService
          .preprocessTextForEntityExtraction(combinedText);
      print("Preprocessed Combined Text: $preprocessedText");

      // Try NER extraction first
      String extractedPrice = await _priceExtractionService
          .extractPriceUsingNER(preprocessedText, _entityExtractor);

      setState(() {
        algorithm = 'NER';
      });

      // Fallback to regex if NER fails
      if (extractedPrice.isEmpty) {
        print("NER extraction failed. Falling back to regex.");
        extractedPrice =
            _priceExtractionService.extractPriceUsingRegex(preprocessedText);
        setState(() {
          algorithm = 'RegEX';
        });
      }

      // Return null if no price was found, otherwise return the extracted price
      return extractedPrice;
    } catch (e) {
      print("Error in price extraction: $e");
      return null;
    }
  }

  // First, add this function to your class to convert CameraImage to File
  // Future<File> convertCameraImageToFile(CameraImage image) async {
  //   try {
  //     // Only stop the stream if it's currently running
  //     if (_cameraController.value.isStreamingImages) {
  //       await _cameraController.stopImageStream();
  //     }
  //     XFile capturedImage =
  //         await _cameraController.takePicture(); // Take the picture
  //     File imageFile = File(capturedImage.path); // Convert XFile to File
  //     return imageFile;
  //   } catch (e) {
  //     print('Error converting camera image to file: $e');
  //     rethrow;
  //   } finally {
  //     // Resume the stream if needed and not paused
  //     if (!_isPaused && !_cameraController.value.isStreamingImages) {
  //       _startImageStream();
  //     }
  //   }
  // }

  // Function to convert CameraImage to InputImage
  InputImage _convertCameraImageToInputImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _getCameraRotation(), // Utility function for rotation
        format:
            InputImageFormat.nv21, // Ensure the format matches camera output
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  // Utility function to get the rotation angle of the image
  // InputImageRotation _getImageRotation() {
  //   // Adjust according to the orientation of your device and camera
  //   // Common values are 0, 90, 180, 270 for rotation angles
  //   return InputImageRotation.rotation0deg;
  // }

  Future<void> _apiResumeStream() async {
    if (_priceController.text.isNotEmpty) {
      try {
        // Wait for API response
        setState(() {
          _isAPIcomplete = false;
        });

        await _apiService.sendPriceExtractionData(
          imageFile: imageFile!,
          price: _priceController.text,
          isCorrect: isCorrect,
          algorithm: algorithm,
        );

        // Only reset the state after successful API response
        setState(() {
          _isPaused = !_isPaused;
          _priceController.text = '';
        });
      } catch (e) {
        // Handle API error
        print("Error sending data to API: $e");
        // Optionally show error to user using ScaffoldMessenger
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send data. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      // If no price text, just toggle the stream
      setState(() {
        _isPaused = !_isPaused;
        _priceController.text = '';
      });
    }
    setState(() {
      _isAPIcomplete = true;
    });
  }

  bool _isLandscape(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  Future<void> startPriceScanning(
      Completer<Product?> completer, List<Product> products) async {
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        throw Exception("Camera is not initialized");
      }
      if (_cameraController!.value.isStreamingImages) return;

      await _cameraController!.startImageStream((CameraImage image) async {
        try {
          String? price = await _processImageForPriceExtraction(image);
          print(price);
          if (price != null) {
            if (_cameraController!.value.isStreamingImages) {
              await _cameraController!.stopImageStream();
            }

            // Find product with matching price
            Product? matchingProduct = products
                    .any((product) => product.salesPrice.toString() == price)
                ? products.firstWhere(
                    (product) => product.salesPrice.toString() == price)
                : null;

            if (!completer.isCompleted) {
              completer.complete(matchingProduct);
            }
          }
        } catch (e) {
          if (_cameraController!.value.isStreamingImages) {
            await _cameraController!.stopImageStream();
          }
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      });
    } catch (e) {
      print("Error in price scanning: $e");
      completer.completeError(e);
    }
  }

  Future<Product?> productDetails() async {
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        throw Exception("Camera is not initialized");
      }
      if (_cameraController!.value.isStreamingImages) return null;

      final completer = Completer<Product?>();
      String? scannedBarcode;

      // Phase 1: Barcode Scanning
      await _cameraController!.startImageStream((CameraImage image) async {
        if (scannedBarcode != null) {
          if (_cameraController!.value.isStreamingImages) {
            await _cameraController!.stopImageStream();
          }
          return;
        }

        try {
          String? barcode = await _startBarcodeScanning(image);
          print(barcode);
          if (barcode != null) {
            scannedBarcode = barcode;

            if (_cameraController!.value.isStreamingImages) {
              await _cameraController!.stopImageStream();
            }
            print('after stopping');

            // Get products for scanned barcode
            //print("PASSING TO API");
            List<Product> productList = sample;
            //List<Product> productList =await _apiService.getProductByBarcode(barcode);
            // print('RETURNING FROM API');
            if (productList.length == 1) {
              // Single product - return it immediately
              completer.complete(productList.first);
            } else if (productList.length > 1) {
              // Multiple products - start price scanning
              await startPriceScanning(completer, productList);
            } else {
              // No products found
              completer.complete(null);
            }
          }
        } catch (e) {
          if (_cameraController!.value.isStreamingImages) {
            await _cameraController!.stopImageStream();
          }
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      });

      return completer.future;
    } catch (e) {
      print("Error in productDetails: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text("Scan Product")),
      body: Stack(
        children: [
          CameraPreview(_cameraController!), // Show the camera view
          Center(
            child: _isScanning
                ? CircularProgressIndicator()
                : Text("Point camera at product",
                    style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}

//   @override
//   Widget build(BuildContext context) {
//     double screenWidth = MediaQuery.sizeOf(context).width;
//     double screenHeigth = MediaQuery.sizeOf(context).height;

//     return Scaffold(
//         resizeToAvoidBottomInset: false,
//         appBar: AppBar(
//           backgroundColor: Colors.green,
//           title: Text(
//             "PRICE EXTRACTOR",
//             style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
//           ),
//           centerTitle: true,
//         ),
//         body: Stack(
//           children: [
//             buildnew(),
//             // OrientationBuilder(
//             //   builder: (context, orientation) {
//             //     return orientation == Orientation.portrait
//             //         ? buildPortraitLayout(screenHeigth, screenWidth)
//             //         : buildLandscapeLayout(screenHeigth, screenWidth);
//             //   },
//             // ),
//             // if (!_isAPIcomplete)
//             //   Positioned.fill(
//             //     child: Container(
//             //       color: const Color.fromARGB(152, 0, 0, 0),
//             //       child: Column(
//             //         mainAxisAlignment: MainAxisAlignment.center,
//             //         children: [
//             //           CircularProgressIndicator(
//             //             color: Colors.grey,
//             //           ),
//             //           SizedBox(
//             //             height: MediaQuery.sizeOf(context).height * 0.03,
//             //           ),
//             //           Text(
//             //             'Storing Data...',
//             //             style: TextStyle(
//             //                 color: Colors.grey[200],
//             //                 fontStyle: FontStyle.italic),
//             //           )
//             //         ],
//             //       ),
//             //     ),
//             //   ),
//           ],
//         ));
//   }

//   Widget buildnew() {
//     return Expanded(
//       child: Center(
//         child: AspectRatio(
//           key: UniqueKey(),
//           aspectRatio: 9 / 16,
//           child: ClipRRect(
//             borderRadius:
//                 BorderRadius.circular(20), // Adjust the radius as needed
//             child: CameraPreview(_cameraController),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget buildPortraitLayout(double screenheight, double screenWidth) {
//     return Padding(
//       padding: const EdgeInsets.all(5),
//       child: Column(
//         children: [
//           SizedBox(
//             height: screenheight * 0.01,
//           ),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//             children: [
//               _priceField(),
//               ToggleButtons(
//                 direction: Axis.horizontal,
//                 borderRadius: BorderRadius.circular(15),
//                 selectedColor: Colors.green[800],
//                 selectedBorderColor: Colors.green[800],
//                 children: const [
//                   Icon(Icons.barcode_reader),
//                   Icon(Icons.attach_money),
//                 ],
//                 onPressed: (int index) {
//                   setState(() {
//                     _isBarcodeScanner = !_isBarcodeScanner;
//                   });
//                 },
//                 isSelected: [_isBarcodeScanner, !_isBarcodeScanner],
//               ),
//             ],
//           ),
//           SizedBox(
//             height: MediaQuery.sizeOf(context).height * 0.01,
//           ),
//           Text("Scan the price tag here"),
//           if (_isCameraInitialized)
//             Expanded(
//               child: Center(
//                 child: AspectRatio(
//                   key: UniqueKey(),
//                   aspectRatio: 9 / 16,
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(
//                         20), // Adjust the radius as needed
//                     child: CameraPreview(_cameraController),
//                   ),
//                 ),
//               ),
//             ),
//           SizedBox(
//             height: 20,
//           ),
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Expanded(
//                 child: MaterialButton(
//                   height: MediaQuery.sizeOf(context).height * 0.07,
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10)),
//                   color: Colors.green,
//                   onPressed: _isAPIcomplete
//                       ? () {
//                           setState(() {
//                             _isPaused = !_isPaused;
//                             _priceController.text = '';
//                           });
//                         }
//                       : null,
//                   disabledColor: Colors.grey,
//                   child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
//                 ),
//               ),
//               SizedBox(
//                 width: MediaQuery.sizeOf(context).width * 0.05,
//               ),
//               Expanded(
//                 child: MaterialButton(
//                   height: MediaQuery.sizeOf(context).height * 0.07,
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10)),
//                   color: Colors.green,
//                   onPressed: _priceController.text.isNotEmpty
//                       ? () async {
//                           await _apiResumeStream();
//                         }
//                       : null,
//                   disabledColor: Colors.grey,
//                   child: Icon(Icons.check),
//                 ),
//               )
//             ],
//           )
//         ],
//       ),
//     );
//   }

//   IntrinsicWidth _priceField() {
//     return IntrinsicWidth(
//       child: Container(
//         padding: EdgeInsets.all(10),
//         height: MediaQuery.sizeOf(context).height * 0.07,
//         //width: MediaQuery.sizeOf(context).width * 0.4,
//         decoration: BoxDecoration(
//           color: Colors.grey[300], // Light green background
//           borderRadius: BorderRadius.circular(12), // Rounded corners
//           border: Border.all(
//             color: Colors.black, // Dark green border
//             width: 2,
//           ),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.grey.withOpacity(0.3),
//               spreadRadius: 2,
//               blurRadius: 5,
//               offset: Offset(2, 3), // Adds a slight shadow
//             ),
//           ],
//         ),
//         child: SizedBox(
//           width: MediaQuery.sizeOf(context).width * 0.5,
//           child: !_isPaused
//               ? Center(
//                   child: CircularProgressIndicator(
//                     color: Colors.blueGrey,
//                   ),
//                 )
//               : !_isBarcodeScanner
//                   ? Row(
//                       crossAxisAlignment: CrossAxisAlignment.center,
//                       children: [
//                         Icon(
//                           Icons.currency_rupee_outlined, // Currency icon
//                           color: Colors.green[800],
//                           size: 26,
//                         ),
//                         SizedBox(width: 5),
//                         Expanded(
//                           child: TextField(
//                             controller: _priceController,
//                             keyboardType: TextInputType.numberWithOptions(),
//                             style: TextStyle(
//                               fontSize: 26,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.green[800],
//                             ),
//                             decoration: InputDecoration(
//                               isCollapsed: true,
//                               border: InputBorder.none,
//                               hintText: "Enter price",
//                               hintStyle: TextStyle(
//                                 fontSize: 26,
//                                 fontWeight: FontWeight.w400,
//                                 color: Colors.grey[400],
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                     )
//                   : Text(_barcode),
//         ),
//       ),
//     );
//   }

//   Widget buildLandscapeLayout(double screenheight, double screenWidth) {
//     return Padding(
//       padding: const EdgeInsets.all(5),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           SizedBox(
//             height: MediaQuery.sizeOf(context).height * 0.01,
//           ),
//           Column(
//             children: [
//               const Text("Scan the price tag here"),
//               if (_isCameraInitialized)
//                 Center(
//                   child: Container(
//                     height: screenheight * 0.7,
//                     width: screenWidth * 0.5,
//                     child: AspectRatio(
//                       aspectRatio: 16 / 9,
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(
//                             20), // Adjust the radius as needed
//                         child: CameraPreview(_cameraController),
//                       ),
//                     ),
//                   ),
//                 ),
//             ],
//           ),
//           Column(
//             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//             children: [
//               _priceField(),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   SizedBox(
//                     width: MediaQuery.sizeOf(context).width * 0.1,
//                     child: MaterialButton(
//                       disabledColor: Colors.grey,
//                       height: MediaQuery.sizeOf(context).height * 0.2,
//                       shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(10)),
//                       color: Colors.green,
//                       onPressed: _isAPIcomplete
//                           ? () {
//                               setState(() {
//                                 _isPaused = !_isPaused;
//                                 _priceController.text = '';
//                               });
//                             }
//                           : null,
//                       child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
//                     ),
//                   ),
//                   SizedBox(
//                     width: MediaQuery.sizeOf(context).width * 0.05,
//                   ),
//                   SizedBox(
//                     width: MediaQuery.sizeOf(context).width * 0.1,
//                     child: MaterialButton(
//                       height: MediaQuery.sizeOf(context).height * 0.2,
//                       shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(10)),
//                       color: Colors.green,
//                       onPressed: _priceController.text.isNotEmpty
//                           ? () async {
//                               await _apiResumeStream();
//                             }
//                           : null,
//                       disabledColor: Colors.grey,
//                       child: Icon(Icons.check),
//                     ),
//                   )
//                 ],
//               )
//             ],
//           ),
//           SizedBox(
//             height: MediaQuery.sizeOf(context).height * 0.01,
//           )
//         ],
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     // Stop the image stream before disposing
//     if (_cameraController.value.isStreamingImages) {
//       _cameraController.stopImageStream();
//     }
//     _cameraController.dispose();
//     _textRecognizer.close();
//     _entityExtractor.close();
//     _priceController.dispose();
//     _barcodeScanner.close();
//     super.dispose();
//   }
// }
