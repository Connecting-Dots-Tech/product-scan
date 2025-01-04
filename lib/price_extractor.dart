import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
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

  late EntityExtractor _entityExtractor;
  final PriceExtractionService _priceExtractionService =
      PriceExtractionService();
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

          // Fallback to regex if NER fails (returns empty string)
          if (extractedPrice.isEmpty) {
            print("NER extraction failed. Falling back to regex.");
            extractedPrice = _priceExtractionService
                .extractPriceUsingRegex(preprocessedText);
          }

          if (extractedPrice.isNotEmpty) {
            print("Extracted Price: $extractedPrice");
            setState(() {
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

  void _resumeStream() {
    setState(() {
      _isPaused = !_isPaused;
      _priceController.text = '';
    });
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.1,
        child: FloatingActionButton.extended(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: Colors.green,
          label: Icon(
            _priceController.text.isEmpty
                ? _isPaused
                    ? Icons.play_arrow
                    : Icons.pause
                : Icons.check_box,
            color: Colors.white,
            size: 50,
          ),
          onPressed: _resumeStream,
        ),
      ),
      body: Padding(
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
                child: !_isPaused
                    ? CircularProgressIndicator(
                        color: Colors.blueGrey,
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
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.01,
            ),
            Text("Scan the price tag here"),
            if (_isCameraInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: 2 / 2.9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                        20), // Adjust the radius as needed
                    child: CameraPreview(_cameraController),
                  ),
                ),
              ),
            SizedBox(
              height: 20,
            ),
          ],
        ),
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
