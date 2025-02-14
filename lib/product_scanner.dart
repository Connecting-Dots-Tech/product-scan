import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:delightful_toast/delight_toast.dart';
import 'package:delightful_toast/toast/components/toast_card.dart';
import 'package:delightful_toast/toast/utils/enums.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

import 'package:price_snap/api_service.dart';

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

typedef ProductCallback = void Function(ProductModel? product);

class PriceExtractorApp extends StatefulWidget {
  final String url;
  final ProductCallback onResult;
  const PriceExtractorApp(
      {required this.url, required this.onResult, super.key});

  @override
  PriceExtractorAppState createState() => PriceExtractorAppState();
}

class PriceExtractorAppState extends State<PriceExtractorApp> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.all]);
  late EntityExtractor _entityExtractor;
  late PriceExtractionService _priceExtractionService;

  final TextEditingController _inputController = TextEditingController();
  ApiService apiservice = ApiService();

  // bool _isCameraInitialized = false;

  bool _isScanning = false;

  ProductModel? product;

  ScanningState _scanningState = ScanningState.preparingCamera;
  String _statusMessage = "Initializing camera...";

  Timer? _priceInputTimer;

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
      await _cameraController!
          .lockCaptureOrientation(DeviceOrientation.portraitUp);
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
    Navigator.pop(context);
    widget.onResult(product);
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
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888, // Ensure the format matches camera
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  InputImageRotation _getCameraRotation() {
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

  Future<ProductModel?> productDetails() async {
    try {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        throw Exception("Camera is not initialized");
      }

      final completer = Completer<ProductModel?>();
      String? scannedBarcode;
      bool isPriceScanning = false;
      List<ProductModel>? productList;
      bool isProcessing = false;
      bool isManualInputRequested = false;

      print('SCANNING STARTED');
      setState(() {
        _scanningState = ScanningState.scanningBarcode;
        _statusMessage = "Point camera at product barcode";
      });

      await _cameraController!.startImageStream((CameraImage image) async {
        if (completer.isCompleted || isProcessing || isManualInputRequested)
          return;

        try {
          isProcessing = true;

          if (scannedBarcode == null && !isPriceScanning) {
            String? barcode = await _startBarcodeScanning(image);
            if (barcode != null) {
              scannedBarcode = barcode;
              print('SCANNED BARCODE: $barcode');

              setState(() {
                _scanningState = ScanningState.fetchingProduct;
                _statusMessage = "Fetching Product...";
              });

              productList =
                  await apiservice.getProductByBarcode(barcode, widget.url);
              productList = productList!
                  .where((product) => product.barcode == barcode)
                  .toList();

              if (productList!.isEmpty) {
                if (_cameraController!.value.isStreamingImages) {
                  await _cameraController!.stopImageStream();
                }
                setState(() {
                  _scanningState = ScanningState.complete;
                  _statusMessage = "No products found with this barcode";
                });
                completer.complete(null);
              } else if (productList!.length == 1) {
                if (_cameraController!.value.isStreamingImages) {
                  await _cameraController!.stopImageStream();
                }
                setState(() {
                  _scanningState = ScanningState.complete;
                  _statusMessage = "Product found!";
                });
                completer.complete(productList!.first);
              } else {
                isPriceScanning = true;
                setState(() {
                  _scanningState = ScanningState.scanningPrice;
                  _statusMessage = "Point camera at price tag";
                });
                DelightToastBar(
                        position: DelightSnackbarPosition.top,
                        builder: (context) => Center(
                              child: IntrinsicWidth(
                                child: ToastCard(
                                  color: Colors.black54,
                                  leading: Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: Colors.white60,
                                        borderRadius: BorderRadius.circular(6)),
                                    child: Icon(Icons.price_change,
                                        color: Colors.green[700]),
                                  ),
                                  title: Container(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(
                                      'Scan Price Tag with MRP',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        animationDuration: Duration(milliseconds: 100),
                        snackbarDuration: Duration(milliseconds: 1000),
                        autoDismiss: true)
                    .show(context);

                _priceInputTimer?.cancel();
                _priceInputTimer = Timer(Duration(seconds: 6), () async {
                  if (!completer.isCompleted && !isManualInputRequested) {
                    isManualInputRequested = true;
                    if (_cameraController!.value.isStreamingImages) {
                      await _cameraController!.stopImageStream();
                    }

                    setState(() {
                      _scanningState = ScanningState.manualPriceInput;
                      _statusMessage = "Price not found. Please select MRP";
                    });

                    final double? enteredPrice = await showDialog<double>(
                      context: context,
                      builder: (BuildContext context) => AlertDialog(
                        backgroundColor: Colors.white54,
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 5,
                            ),
                            Text(
                              "Select Product MRP",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black),
                            ),
                            IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: Icon(
                                Icons.cancel_outlined,
                                color: Colors.black,
                                size: 30,
                              ),
                            ),
                          ],
                        ),
                        content: Container(
                          width: MediaQuery.of(context).size.width * 0.7,
                          height: min(
                              MediaQuery.of(context).size.height *
                                  0.6, // Max height (60% of screen)
                              100.0 +
                                  (productList!.length / 3).ceil() *
                                      50.0 // Base height + rows height
                              ),
                          padding: const EdgeInsets.all(15),
                          child: Scrollbar(
                            thickness: 6,
                            radius: Radius.circular(3),
                            thumbVisibility: true,
                            child: GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 4,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: productList!.length,
                              itemBuilder: (context, index) {
                                return InkWell(
                                  onTap: () {
                                    Navigator.pop(
                                      context,
                                      double.tryParse(
                                          productList![index].bmrp.toString()),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white60,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                        child: RichText(
                                      text: TextSpan(
                                        text: 'MRP : ',
                                        style: TextStyle(
                                          color: Colors.black45,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '${productList![index].bmrp}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );

                    ProductModel? matchedProduct;
                    if (enteredPrice != null) {
                      matchedProduct = productList!.any((product) =>
                              double.tryParse(product.bmrp.toString()) ==
                              double.tryParse(enteredPrice.toString()))
                          ? productList!.firstWhere((product) =>
                              double.tryParse(product.bmrp.toString()) ==
                              double.tryParse(enteredPrice.toString()))
                          : null;
                    }

                    setState(() {
                      _scanningState = ScanningState.complete;
                      _statusMessage = matchedProduct != null
                          ? "Product found!"
                          : "No matching product found";
                    });

                    if (!completer.isCompleted) {
                      completer.complete(matchedProduct);
                    }
                  }
                });
              }
            }
          } else if (isPriceScanning &&
              productList != null &&
              !isManualInputRequested) {
            _priceExtractionService =
                PriceExtractionService(_textRecognizer, _entityExtractor);
            final inputImage = _convertCameraImageToInputImage(image);

            String? scannedPrice =
                await _priceExtractionService.extractPriceFromImage(inputImage);
            print('SCANNED PRICE:$scannedPrice');

            if (scannedPrice != null) {
              ProductModel? matchingProduct = productList!.any((product) =>
                      double.tryParse(product.bmrp.toString()) ==
                      double.tryParse(scannedPrice))
                  ? productList!.firstWhere((product) =>
                      double.tryParse(product.bmrp.toString()) ==
                      double.tryParse(scannedPrice))
                  : null;

              if (matchingProduct != null && !completer.isCompleted) {
                print('MATCHED PRODUCT PRICE: ${matchingProduct.bmrp}');
                _priceInputTimer?.cancel();
                isManualInputRequested = true;

                if (_cameraController!.value.isStreamingImages) {
                  await _cameraController!.stopImageStream();
                }

                setState(() {
                  _scanningState = ScanningState.complete;
                  _statusMessage = "Product found!";
                });

                completer.complete(matchingProduct);
              }
            }
          }

          isProcessing = false;
        } catch (e) {
          print("Error in scanning: $e");
          isProcessing = false;
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.green,
              ),
              SizedBox(height: 20),
              Text(_statusMessage),
            ],
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Makes background transparent
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          "Scan Product",
          style: TextStyle(color: Colors.white70),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Camera Preview - Full Screen
          SizedBox.expand(
            child: CameraPreview(_cameraController!),
          ),

          // Scanning overlay
          Center(
            child: Container(
              width: isLandscape ? size.height * 0.5 : size.width * 0.5,
              height: isLandscape ? size.height * 0.5 : size.width * 0.5,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Status message
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 24,
              ),
              color: Colors.black54,
              child: Column(
                children: [
                  PreferredSize(
                    preferredSize: Size.fromHeight(4.0),
                    child: LinearProgressIndicator(
                      value: _getProgressValue(),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ),
                  SizedBox(height: size.height * 0.01),
                  Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  // SizedBox(height: 8),
                  // Text(
                  //   _getScanningStepText(),
                  //   style: TextStyle(color: Colors.white70, fontSize: 14),
                  //   textAlign: TextAlign.center,
                  // ),
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
