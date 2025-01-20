import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:price_snap/pricechecker_api_service.dart';
import 'price_extraction_service.dart';

class PriceExtractorNERApp extends StatefulWidget {
  const PriceExtractorNERApp({super.key});

  @override
  _PriceExtractorNERAppState createState() => _PriceExtractorNERAppState();
}

class _PriceExtractorNERAppState extends State<PriceExtractorNERApp> {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isPaused = false;
  final TextRecognizer _textRecognizer = TextRecognizer();
  bool _isAPIcomplete = true;

  File? imageFile; // Placeholder for image file
  String? price; // TextField value
  bool isCorrect = true; // Flag for correctness
  String algorithm = ''; // Algorithm name ('NER' or 'regEX')

  late EntityExtractor _entityExtractor;
  final PriceExtractionService _priceExtractionService =
      PriceExtractionService();
  final PriceExtractionApiService _apiService = PriceExtractionApiService();
  TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
      await _cameraController.initialize();
      setState(() {
        _isCameraInitialized = true;
      });
      _startImageStream();
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  void _startImageStream() {
    _cameraController.startImageStream((CameraImage image) async {
      if (!_isProcessing && !_isPaused) {
        setState(() {
          _isProcessing = true;
        });
        try {
          // Convert CameraImage to InputImage using the new function
          final inputImage = _convertCameraImageToInputImage(image);

          // Recognize text from the image using the TextRecognizer API
          final recognizedText = await _textRecognizer.processImage(inputImage);
          print("Recognized Text: ${recognizedText.text}");

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

          // Extract horizontally aligned text and combine with the keyword
          String combinedText = _priceExtractionService.extractCombinedText(
              recognizedText.blocks, priceKeywords);
          print("Combined Text before preprocessing: $combinedText");

          // Preprocess the combined text before extracting price
          String preprocessedText = _priceExtractionService
              .preprocessTextForEntityExtraction(combinedText);
          print("Preprocessed Combined Text: $preprocessedText");

          // Try extracting price using NER
          String extractedPrice = await _priceExtractionService
              .extractPriceUsingNER(preprocessedText, _entityExtractor);
          setState(() {
            algorithm = 'NER';
          });

          // Fallback to regex if NER fails (returns empty string)
          if (extractedPrice.isEmpty) {
            print("NER extraction failed. Falling back to regex.");
            extractedPrice = _priceExtractionService
                .extractPriceUsingRegex(preprocessedText);
            setState(() {
              algorithm = 'RegEX';
            });
          }

          if (extractedPrice.isNotEmpty) {
            print("Extracted Price: $extractedPrice");
            File capturedFile = await convertCameraImageToFile(image);
            setState(() {
              imageFile = capturedFile;
              _priceController.text = extractedPrice;
              _isPaused = true; // Pause the stream on successful extraction
            });
          }
        } catch (e) {
          print("Error processing image: $e");
        } finally {
          setState(() {
            _isProcessing = false;
          });
        }
      }
    });
  }

  // First, add this function to your class to convert CameraImage to File
  Future<File> convertCameraImageToFile(CameraImage image) async {
    try {
      // Pause the stream
      _cameraController.stopImageStream();

      // Take the picture
      XFile capturedImage = await _cameraController.takePicture();

      // Convert XFile to File
      File imageFile = File(capturedImage.path);

      return imageFile;
    } finally {
      // Resume the stream if needed and not paused
      if (!_isPaused) {
        _startImageStream();
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
        rotation: _getImageRotation(), // Utility function for rotation
        format:
            InputImageFormat.nv21, // Ensure the format matches camera output
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  // Utility function to get the rotation angle of the image
  InputImageRotation _getImageRotation() {
    // Adjust according to the orientation of your device and camera
    // Common values are 0, 90, 180, 270 for rotation angles
    return InputImageRotation.rotation0deg;
  }

  Future<void> _resumeStream() async {
    if (_priceController.text.isNotEmpty) {
      try {
        // Wait for API response

        await _apiService.sendDataToAPI(
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
  }

  bool _isLandscape(BuildContext context) {
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.green,
          title: Text(
            "PRICE EXTRACTOR",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          centerTitle: true,
        ),
        // floatingActionButtonLocation: _isLandscape(context)
        //     ? FloatingActionButtonLocation.endFloat
        //     : FloatingActionButtonLocation.endTop,
        // floatingActionButton: SizedBox(
        //   height: _isLandscape(context)
        //       ? MediaQuery.sizeOf(context).height * 0.2
        //       : MediaQuery.sizeOf(context).height * 0.1,
        //   child: FloatingActionButton.extended(
        //     shape:
        //         RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        //     materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        //     backgroundColor: Colors.green,
        //     label: Icon(
        //       _isPaused ? Icons.play_arrow : Icons.pause,
        //       color: Colors.white,
        //       size: 50,
        //     ),
        //     onPressed: () async {
        //       //Print debug information
        //       print('Image: $imageFile');
        //       print('Price: ${_priceController.text}');
        //       print('IsCorrect: $isCorrect');
        //       print('Algorithm: $algorithm');

        //       // Call the async _resumeStream
        //       await _resumeStream();
        //     },
        //   ),
        // ),
        body: Stack(
          children: [
            OrientationBuilder(
              builder: (context, orientation) {
                return orientation == Orientation.portrait
                    ? buildPortraitLayout()
                    : buildLandscapeLayout();
              },
            ),
            if (!_isAPIcomplete)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ));
  }

  Widget buildPortraitLayout() {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.01,
          ),
          IntrinsicWidth(
            child: Container(
              padding: EdgeInsets.all(10),
              height: MediaQuery.sizeOf(context).height * 0.07,
              //width: MediaQuery.sizeOf(context).width * 0.4,
              decoration: BoxDecoration(
                color: Colors.grey[300], // Light green background
                borderRadius: BorderRadius.circular(12), // Rounded corners
                border: Border.all(
                  color: Colors.black, // Dark green border
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: Offset(2, 3), // Adds a slight shadow
                  ),
                ],
              ),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.5,
                child: !_isPaused
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Colors.blueGrey,
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.currency_rupee_outlined, // Currency icon
                            color: Colors.green[800],
                            size: 26,
                          ),
                          SizedBox(width: 5),
                          Expanded(
                            child: TextField(
                              controller: _priceController,
                              keyboardType: TextInputType.numberWithOptions(),
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w500,
                                color: Colors.green[800],
                              ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: "Enter price",
                                hintStyle: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.01,
          ),
          Text("Scan the price tag here"),
          if (_isCameraInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: 2 / 2.6,
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(20), // Adjust the radius as needed
                  child: CameraPreview(_cameraController),
                ),
              ),
            ),
          SizedBox(
            height: 20,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: MaterialButton(
                  height: MediaQuery.sizeOf(context).height * 0.07,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  color: Colors.green,
                  onPressed: () {
                    setState(() {
                      _isPaused = !_isPaused;
                      _priceController.text = '';
                    });
                  },
                  child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                ),
              ),
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.05,
              ),
              Expanded(
                child: MaterialButton(
                  height: MediaQuery.sizeOf(context).height * 0.07,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  color: Colors.green,
                  onPressed: _priceController.text.isNotEmpty
                      ? () async {
                          await _resumeStream();
                        }
                      : null,
                  disabledColor: Colors.grey,
                  child: Icon(Icons.check),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget buildLandscapeLayout() {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.01,
          ),
          Column(
            children: [
              const Text("Scan the price tag here"),
              if (_isCameraInitialized)
                Center(
                  child: Container(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    width: MediaQuery.sizeOf(context).width * 0.5,
                    child: AspectRatio(
                      aspectRatio: 2 / 2.9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            20), // Adjust the radius as needed
                        child: CameraPreview(_cameraController),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IntrinsicWidth(
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: 20),
                  padding: EdgeInsets.all(10),
                  height: MediaQuery.sizeOf(context).height * 0.15,
                  //width: MediaQuery.sizeOf(context).width * 0.4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300], // Light green background
                    borderRadius: BorderRadius.circular(12), // Rounded corners
                    border: Border.all(
                      color: Colors.black, // Dark green border
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: Offset(2, 3), // Adds a slight shadow
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 180,
                    child: !_isPaused
                        ? Center(
                            child: CircularProgressIndicator(
                              color: Colors.blueGrey,
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.currency_rupee_outlined, // Currency icon
                                color: Colors.green[800],
                                size: 26,
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: TextField(
                                  controller: _priceController,
                                  keyboardType:
                                      TextInputType.numberWithOptions(),
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.green[800],
                                  ),
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                    hintText: "Enter price",
                                    hintStyle: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.1,
                    child: MaterialButton(
                      height: MediaQuery.sizeOf(context).height * 0.2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      color: Colors.green,
                      onPressed: () {
                        setState(() {
                          _isPaused = !_isPaused;
                          _priceController.text = '';
                        });
                      },
                      child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.05,
                  ),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.1,
                    child: MaterialButton(
                      height: MediaQuery.sizeOf(context).height * 0.2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      color: Colors.green,
                      onPressed: _priceController.text.isNotEmpty
                          ? () async {
                              await _resumeStream();
                            }
                          : null,
                      disabledColor: Colors.grey,
                      child: Icon(Icons.check),
                    ),
                  )
                ],
              )
            ],
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.01,
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _textRecognizer.close();
    _entityExtractor.close();
    _priceController.dispose();
    super.dispose();
  }
}
