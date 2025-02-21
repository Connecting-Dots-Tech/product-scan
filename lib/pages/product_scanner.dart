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
import 'package:permission_handler/permission_handler.dart';

import 'package:price_snap/model/product_model.dart';

import '../services/api_service.dart';
import '../services/price_extraction_service.dart';

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

class ProductScanner extends StatefulWidget {
  final String url;
  final ProductCallback onResult;
  const ProductScanner({required this.url, required this.onResult, super.key});

  @override
  ProductScannerState createState() => ProductScannerState();
}

class ProductScannerState extends State<ProductScanner> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final EntityExtractor _entityExtractor =
      EntityExtractor(language: EntityExtractorLanguage.english);

  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.all]);

  late PriceExtractionService _priceExtractionService;

  ApiService apiservice = ApiService();

  // bool _isCameraInitialized = false;
  String errormessage = '';

  bool _isScanning = false;

  ProductModel? product;

  ScanningState _scanningState = ScanningState.preparingCamera;
  String _statusMessage = "Opening Scanner...";

  Timer? _priceInputTimer;

  List<CameraDescription> cameras = [];
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      _initializeCamera();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera permission is required'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () async {
                await openAppSettings();
              },
            ),
            duration: Duration(seconds: 5),
          ),
        );
        // Return to previous screen since we can't proceed without camera
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    _selectedCameraIndex = 0;

    _cameraController = CameraController(
      cameras[_selectedCameraIndex],
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!
          .lockCaptureOrientation(DeviceOrientation.portraitUp);
      //_handleRefresh();
      //_isCameraInitialized = true;

      _startScanning();
    } catch (e) {
      print("Camera initialization error: $e");
      setState(() {
        _statusMessage = "Error initializing camera";
      });
    }
  }

  Future<void> _toggleCameraUsingSetDescription() async {
    try {
      // Stop current image stream if running
      if (_cameraController?.value.isStreamingImages ?? false) {
        await _cameraController?.stopImageStream();
      }

      // Toggle camera index
      _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;

      setState(() {
        _scanningState = ScanningState.preparingCamera;
        _statusMessage = "Switching camera...";
        _isScanning = false;
      });

      // Set new camera description
      await _cameraController?.setDescription(cameras[_selectedCameraIndex]);

      // Reinitialize with new description
      await _cameraController?.initialize();
      await _cameraController
          ?.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Restart scanning
      _startScanning();
    } catch (e) {
      print("Error switching camera: $e");
    }
  }

  Future<void> _startScanning() async {
    if (_cameraController == null || _isScanning) return;

    try {
      setState(() {
        _isScanning = true;
      });

      product = await productDetails(); // Scan for a product

      // Only pop and return result if the scanning wasn't cancelled
      if (mounted) {
        Navigator.pop(context);
        widget.onResult(product); // Call the callback with the result
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning product: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
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
      ProductModel? matchedProduct;
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

              final response =
                  await apiservice.getProductByBarcode(barcode, widget.url);
              if (!response.isSuccess || response.data == null) {
                // ScaffoldMessenger.of(context).showSnackBar(
                //   SnackBar(
                //       content: Text(response.error ?? 'An error occurred')),
                // );
                setState(() {
                  _scanningState = ScanningState.scanningBarcode;
                  _statusMessage = 'Point camera at product barcode';
                  errormessage = response.error ?? 'An error occurred';
                });
                if (_cameraController!.value.isStreamingImages) {
                  await _cameraController!.stopImageStream();
                }
                // if (!completer.isCompleted) {
                //   completer.complete(null);
                // }

                // Show rescan dialog
                bool? shouldRescan = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text(
                        response.error ?? 'Scanning Failed',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: Text(
                        'Do you want to scan again ?',
                        style: TextStyle(fontSize: 16),
                      ),
                      actionsAlignment: MainAxisAlignment.spaceBetween,
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                                color: Colors.green[900],
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(
                              'Ok',
                              style: TextStyle(
                                  color: Colors.green[900],
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                            )),
                      ],
                    );
                  },
                );

                if (shouldRescan == true) {
                  // Stop current image stream
                  if (_cameraController!.value.isStreamingImages) {
                    await _cameraController!.stopImageStream();
                  }

                  // Start a completely new scan cycle
                  await Future.delayed(Duration(milliseconds: 500));
                  scannedBarcode = null;
                  isPriceScanning = false;
                  productList = null;
                  isProcessing = false;
                  isManualInputRequested = false;
                  matchedProduct = null;
                  setState(() {
                    _isScanning = false;
                  });
                  // Instead of calling _handleRefresh, return a new productDetails() call
                  await _startScanning(); // This will create a new completer and start fresh
                  return;
                } else {
                  // User chose to go back
                  setState(() {
                    _scanningState = ScanningState.complete;
                    _statusMessage = "";
                  });
                  if (!completer.isCompleted) {
                    completer.complete(null);
                  }
                }
              }

              productList = response.data;
              // Modified filtering logic to handle barcode variations
              // productList = productList!
              //     .where((product) =>
              //         product.barcode?.split(':')[0].replaceAll(' ', '') ==
              //         barcode.replaceAll(' ', ''))
              //     .toList();
              print(productList);
              if (productList!.isEmpty) {
                if (_cameraController!.value.isStreamingImages) {
                  await _cameraController!.stopImageStream();
                }
                setState(() {
                  _scanningState = ScanningState.complete;
                  _statusMessage = "No products found with this barcode";
                  errormessage = 'No products found with this barcode';
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
                    child: ToastCard(
                      color: Colors.white,
                      title: Container(
                        padding: EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12), // Adds padding for emphasis
                        decoration: BoxDecoration(
                          color: Colors.green[
                              50], // Light green background for highlighting
                          borderRadius:
                              BorderRadius.circular(8), // Smooth corners
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.2),
                              blurRadius: 5,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.price_change,
                                color: Colors.green[900], size: 28),
                            SizedBox(width: 10),
                            Text(
                              ' Scan Price Tag with MRP!',
                              style: TextStyle(
                                fontWeight: FontWeight.w900, // Extra bold
                                fontSize: 18, // Slightly bigger for importance
                                color: Colors.green[
                                    900], // Dark green for high visibility
                                letterSpacing: 0.5, // Improves readability
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  animationDuration: Duration(milliseconds: 100),
                  snackbarDuration: Duration(milliseconds: 1500),
                  autoDismiss: true,
                ).show(context);

                _priceInputTimer?.cancel();
                _priceInputTimer = Timer(Duration(seconds: 6), () async {
                  // Check if we already have a match from scanning
                  if (!completer.isCompleted && !isManualInputRequested) {
                    isManualInputRequested = true;
                    isPriceScanning = false;

                    if (_cameraController!.value.isStreamingImages) {
                      await _cameraController!.stopImageStream();
                    }

                    setState(() {
                      _scanningState = ScanningState.manualPriceInput;
                      _statusMessage = "Price not found. Please select MRP";
                    });

                    final double? selectedPrice = await showDialog<double>(
                      context: context,
                      builder: (BuildContext context) => AlertDialog(
                        backgroundColor: Colors.white60,
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
                                      color: Colors.white,
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

                    if (selectedPrice != null) {
                      matchedProduct = productList!.any((product) =>
                              double.tryParse(product.bmrp.toString()) ==
                              double.tryParse(selectedPrice.toString()))
                          ? productList!.firstWhere((product) =>
                              double.tryParse(product.bmrp.toString()) ==
                              double.tryParse(selectedPrice.toString()))
                          : null;
                    }

                    setState(() {
                      _scanningState = ScanningState.complete;
                      _statusMessage = matchedProduct != null
                          ? "Product found!"
                          : "Scanning Completed";
                    });

                    // Final check before completing
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
              matchedProduct = productList!.any((product) =>
                      double.tryParse(product.bmrp.toString()) ==
                      double.tryParse(scannedPrice))
                  ? productList!.firstWhere((product) =>
                      double.tryParse(product.bmrp.toString()) ==
                      double.tryParse(scannedPrice))
                  : null;

              if (matchedProduct != null && !completer.isCompleted) {
                print('MATCHED PRODUCT PRICE: ${matchedProduct!.bmrp}');
                // Cancel timer first to prevent it from triggering
                _priceInputTimer?.cancel();

                // Set flags before completing the future
                isManualInputRequested = true;
                isPriceScanning = false;

                // Stop camera stream before completing the future
                if (_cameraController!.value.isStreamingImages) {
                  await _cameraController!.stopImageStream();
                }

                setState(() {
                  _scanningState = ScanningState.complete;
                  _statusMessage = "Product found!";
                });

                // Add a small delay to ensure all state updates are processed
                await Future.delayed(Duration(milliseconds: 100));

                // Final check before completing
                if (!completer.isCompleted) {
                  print('Completing with matched product');
                  completer.complete(matchedProduct);
                }
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

  Future<void> _handleRefresh() async {
    setState(() {
      _isScanning = false;
      _scanningState = ScanningState.scanningBarcode;
      _statusMessage = "Point camera at product barcode";
    });
    await _startScanning();
  }

  bool get isFrontCamera {
    return _cameraController?.description.lensDirection ==
        CameraLensDirection.front;
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
          Transform.scale(
            scaleX: isFrontCamera ? 1 : 1,
            scaleY: isFrontCamera ? -1 : 1,
            child: SizedBox.expand(
              child: CameraPreview(_cameraController!),
            ),
          ),

          // Status message

          if (_scanningState != ScanningState.fetchingProduct)
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(height: size.height * 0.01),
                    Text(
                      _statusMessage,
                      style: TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment(0, 0.7),
            child: Container(
              height: 90,
              width: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.7),
              ),
              child: GestureDetector(
                child: const Icon(
                  Icons.flip_camera_android_rounded,
                  size: 50,
                  color: Colors.white,
                ),
                onTap: () async {
                  _toggleCameraUsingSetDescription();
                },
              ),
            ),
          ),
          if (_scanningState == ScanningState.fetchingProduct)
            Container(
              color: Colors.black54,
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      _statusMessage,
                      style: TextStyle(color: Colors.white, fontSize: 18),
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

    _textRecognizer.close();
    _entityExtractor.close();
    _priceInputTimer?.cancel();
    super.dispose();
  }
}
