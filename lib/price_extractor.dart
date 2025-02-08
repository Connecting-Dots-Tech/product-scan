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

enum ScanningState {
  preparingCamera,
  scanningBarcode,
  fetchingProduct,
  scanningPrice,
  manualPriceInput,
  processingData,
  complete
}

class PriceExtractorApp extends StatefulWidget {
  final String url;
  PriceExtractorApp({required this.url, super.key});

  @override
  _PriceExtractorAppState createState() => _PriceExtractorAppState();
}

class _PriceExtractorAppState extends State<PriceExtractorApp> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.all]);
  late EntityExtractor _entityExtractor;
  final PriceExtractionService _priceExtractionService =
      PriceExtractionService();

  final TextEditingController _inputController = TextEditingController();
  ApiService apiservice = ApiService();

  // bool _isCameraInitialized = false;

  bool _isScanning = false;

  Product? product;

  ScanningState _scanningState = ScanningState.preparingCamera;
  String _statusMessage = "Initializing camera...";

  Timer? _priceInputTimer;

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

  late Future<List<Product>> sample;

  // List<Product> testProductList = [
  //   Product(
  //       code: '123',
  //       name: 'Paperage book',
  //       category: 'Book',
  //       brand: 'paperage',
  //       productCode: '123',
  //       bmrp: '55',
  //       barcode: '8906150411104',
  //       discount: '0',
  //       salesPrice: '55'),
  //   Product(
  //       code: '123',
  //       name: 'Paperage book',
  //       category: 'Book',
  //       brand: 'paperage',
  //       productCode: '123',
  //       bmrp: '58',
  //       barcode: '8906150411104',
  //       discount: '0',
  //       salesPrice: '55')
  // ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _entityExtractor =
        EntityExtractor(language: EntityExtractorLanguage.english);
    _inputController.addListener(() {
      setState(() {});
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
      _handleRefresh();
      //_isCameraInitialized = true;

      _startScanning();
    } catch (e) {
      print("Camera initialization error: $e");
      setState(() {
        _statusMessage = "Error initializing camera";
      });
    }
  }

  Future<void> _startScanning() async {
    if (_cameraController == null || _isScanning) return;

    setState(() {
      _isScanning = true;
    });

    product = await productDetails(); // Scan for a product

    if (product != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailsPage(product: product!),
        ),
      );
    } else if (product == null) {
      Navigator.pop(context);
    }

    setState(() {
      _isScanning = false;
    });
  }

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

  InputImageRotation _getCameraRotation() {
    final deviceRotation = _cameraController!.description.sensorOrientation;
    if (deviceRotation == 90) return InputImageRotation.rotation90deg;
    if (deviceRotation == 180) return InputImageRotation.rotation180deg;
    if (deviceRotation == 270) return InputImageRotation.rotation270deg;
    return InputImageRotation.rotation0deg;
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

  Future<String?> _processImageForPriceExtraction(CameraImage image) async {
    try {
      final inputImage = _convertCameraImageToInputImage(image);

      final recognizedText = await _textRecognizer.processImage(inputImage);
      print("Recognized Text: ${recognizedText.text}");

      if (recognizedText.text.isNotEmpty) {
        String combinedText = await _priceExtractionService.extractCombinedText(
            recognizedText.blocks, priceKeywords);
        print("Combined Text before preprocessing: $combinedText");

        if (combinedText.isEmpty) {
          return null;
        }

        String preprocessedText = await _priceExtractionService
            .preprocessTextForEntityExtraction(combinedText);
        print("Preprocessed Combined Text: $preprocessedText");

        String extractedPrice = await _priceExtractionService
            .extractPriceUsingNER(preprocessedText, _entityExtractor);

        if (extractedPrice.isEmpty) {
          print("NER extraction failed. Falling back to regex.");
          extractedPrice = await _priceExtractionService
              .extractPriceUsingRegex(preprocessedText);
        }
        _textRecognizer.close();
        return extractedPrice;
      } else {
        return null;
      }
    } catch (e) {
      print("Error in price extraction: $e");
      return null;
    }
  }

  bool _isLandscape(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  Future<Product?> productDetails() async {
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        throw Exception("Camera is not initialized");
      }

      final completer = Completer<Product?>();
      String? scannedBarcode;
      print('BARCODE SCANNING STARTED');
      setState(() {
        _scanningState = ScanningState.scanningBarcode;
        _statusMessage = "Point camera at product barcode";
      });

      await _cameraController!.startImageStream((CameraImage image) async {
        if (scannedBarcode != null || completer.isCompleted) return;

        try {
          String? barcode = await _startBarcodeScanning(image);
          if (barcode != null) {
            scannedBarcode = barcode;
            print('SCANNED BARCODE: $barcode');

            if (_cameraController!.value.isStreamingImages) {
              await _cameraController!.stopImageStream();
            }

            setState(() {
              _scanningState = ScanningState.fetchingProduct;
              _statusMessage = "Fetching Product...";
            });

            List<Product> productList =
                await apiservice.getProductByBarcode(barcode, widget.url);
            productList = productList
                .where((product) => product.barcode == barcode)
                .toList();

            if (productList.isEmpty) {
              setState(() {
                _scanningState = ScanningState.complete;
                _statusMessage = "No products found with this barcode";
              });
              completer.complete(null);
            } else if (productList.length == 1) {
              setState(() {
                _scanningState = ScanningState.complete;
                _statusMessage = "Product found!";
              });
              completer.complete(productList.first);
            } else {
              setState(() {
                _scanningState = ScanningState.scanningPrice;
                _statusMessage =
                    "Multiple products found. Point camera at price tag";
              });

              // Set timeout for price scanning
              _priceInputTimer?.cancel();
              _priceInputTimer = Timer(Duration(seconds: 5), () async {
                if (!completer.isCompleted) {
                  try {
                    // Stop camera stream
                    if (_cameraController!.value.isStreamingImages) {
                      await _cameraController!.stopImageStream();
                    }
                    if (!mounted) return; // Ensure widget is still active

                    // Update UI state
                    setState(() {
                      _scanningState = ScanningState.complete;
                      _statusMessage = "Price not found. Please enter manually";
                    });

                    // Show manual price input dialog
                    final double? enteredPrice = await showDialog<double>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                              title: Text("Enter Price"),
                              content: TextField(
                                controller: _inputController,
                                keyboardType: TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: InputDecoration(
                                  hintText: "Enter product price",
                                  prefixText: '₹ ',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    final input = _inputController.text;
                                    final sanitized =
                                        input.replaceAll(RegExp(r'[^0-9]'), '');
                                    final price = double.tryParse(sanitized);

                                    if (price != null) {
                                      Navigator.pop(context, price);
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content:
                                                Text("Invalid price format")),
                                      );
                                      Navigator.pop(context);
                                    }
                                  },
                                  child: Text("Confirm"),
                                ),
                              ],
                            ));
                    print('ENTERED PRICE :$enteredPrice');
                    // Find matching product from entered price
                    Product? matProduct;
                    if (enteredPrice != null) {
                      matProduct = productList.any((product) =>
                              double.tryParse(product.bmrp.toString()) ==
                              double.tryParse(enteredPrice.toString()))
                          ? productList.firstWhere((product) =>
                              double.tryParse(product.bmrp.toString()) ==
                              double.tryParse(enteredPrice.toString()))
                          : null;
                    }
                    if (matProduct != null) {
                      // Navigate to ProductDetailsPage
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ProductDetailsPage(product: matProduct!),
                        ),
                      );
                    } else {
                      // Show error message if no product matches the entered price
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text("No product found with this price")),
                      );
                    }
                    if (!completer.isCompleted) {
                      completer.complete(matProduct);
                    }
                  } catch (e) {
                    print("Error in price fallback: $e");
                    if (!completer.isCompleted) completer.complete(null);
                  }
                }
              });

              await startPriceScanning(completer, productList);
            }
          }
        } catch (e) {
          print("Error in scanning: $e");
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
      setState(() {
        _statusMessage = "Error: $e";
      });
      return null;
    }
  }

  Future<void> startPriceScanning(
      Completer<Product?> completer, List<Product> products) async {
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        throw Exception("Camera is not initialized");
      }
      if (_cameraController!.value.isStreamingImages) return;

      bool isProcessing = false; // Flag to prevent multiple processing

      await _cameraController!.startImageStream((CameraImage image) async {
        // Return immediately if completer is completed or already processing
        if (completer.isCompleted || isProcessing) return;

        try {
          isProcessing = true; // Set processing flag
          String? scannedPrice = await _processImageForPriceExtraction(image);
          print('SCANNED PRICE:$scannedPrice');

          if (scannedPrice != null) {
            // Immediately stop the stream
            if (_cameraController!.value.isStreamingImages) {
              await _cameraController!.stopImageStream();
            }

            Product? matchingProduct = products.any((product) =>
                    double.tryParse(product.bmrp.toString()) ==
                    double.tryParse(scannedPrice))
                ? products.firstWhere((product) =>
                    double.tryParse(product.bmrp.toString()) ==
                    double.tryParse(scannedPrice))
                : null;

            if (matchingProduct != null && !completer.isCompleted) {
              print('MATCHED PRODUCT PRICE: ${matchingProduct.bmrp}');
              _priceInputTimer?.cancel();
              setState(() {
                _scanningState = ScanningState.complete;
                _statusMessage = "Product found!";
              });
              completer.complete(matchingProduct);
            } else {
              isProcessing = false; // Reset processing flag if no match found
            }
          } else {
            isProcessing = false; // Reset processing flag if no price found
          }
        } catch (e) {
          print("Error in price scanning: $e");
          isProcessing = false; // Reset processing flag on error
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
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
  }

  void _handleRefresh() async {
    setState(() {
      _isScanning = false;
      _scanningState = ScanningState.scanningBarcode;
      _statusMessage = "Point camera at product barcode";
    });
    _startScanning();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(_statusMessage),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text("Scan Product"),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(4.0),
          child: LinearProgressIndicator(
            value: _getProgressValue(),
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
        ),
      ),
      body: Stack(
        children: [
          Center(
              child: CameraPreview(
            _cameraController!,
            child: Text('data'),
          )),

          // Scanning overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Status message
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              color: Colors.black54,
              child: Column(
                children: [
                  Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    _getScanningStepText(),
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getProgressValue() {
    switch (_scanningState) {
      case ScanningState.preparingCamera:
        return 0.1;
      case ScanningState.scanningBarcode:
        return 0.3;
      case ScanningState.fetchingProduct:
        return 0.5;
      case ScanningState.scanningPrice:
        return 0.6;
      case ScanningState.manualPriceInput:
        return 0.66;
      case ScanningState.processingData:
        return 0.83;
      case ScanningState.complete:
        return 1.0;
    }
  }

  String _getScanningStepText() {
    switch (_scanningState) {
      case ScanningState.preparingCamera:
        return "Step 1/6: Preparing camera";
      case ScanningState.scanningBarcode:
        return "Step 2/6: Scanning barcode";
      case ScanningState.fetchingProduct:
        return "Step 3/6: Fetching product";
      case ScanningState.scanningPrice:
        return "Step 4/6: Scanning price";
      case ScanningState.manualPriceInput:
        return "Step 5/6: Manual price input";
      case ScanningState.processingData:
        return "Step 6/6: Processing data";
      case ScanningState.complete:
        return "Complete!";
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeScanner.close();
    _inputController.dispose();
    _textRecognizer.close();
    _entityExtractor.close();
    _priceInputTimer?.cancel();
    super.dispose();
  }
}
