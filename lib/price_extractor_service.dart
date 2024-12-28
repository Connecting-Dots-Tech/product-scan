import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

class PriceExtractorNERApp extends StatefulWidget {
  const PriceExtractorNERApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _PriceExtractorNERAppState createState() => _PriceExtractorNERAppState();
}

class _PriceExtractorNERAppState extends State<PriceExtractorNERApp> {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  final TextRecognizer _textRecognizer = TextRecognizer();
  late EntityExtractor _entityExtractor;
  String _extractedPrice = "";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _entityExtractor =
        EntityExtractor(language: EntityExtractorLanguage.english);
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
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  Future<void> _processImage() async {
    if (_cameraController.value.isTakingPicture || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final picture = await _cameraController.takePicture();
      final inputImage = InputImage.fromFilePath(picture.path);

      // Recognize text from the image using the TextRecognizer API
      final recognizedText = await _textRecognizer.processImage(inputImage);
      print("Recognized Text: ${recognizedText.text}");
      _textRecognizer.close();
      // Extract price using NER
      String nerPrice = await _extractPriceUsingRegex(recognizedText.text);
      //String nerPrice = await _extractPriceUsingNER(recognizedText.text);

      setState(() {
        _extractedPrice = nerPrice;
      });
    } catch (e) {
      print("Error processing image: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Method to extract price using Named Entity Recognition (NER)
  Future<String> _extractPriceUsingNER(String text) async {
    final List<EntityAnnotation> entityAnnotations = await _entityExtractor
        .annotateText(text, entityTypesFilter: [EntityType.money]);

    for (var annotation in entityAnnotations) {
      return annotation.text;
    }

    return "No price found";
  }

  Future<String> _extractPriceUsingRegex(String text) async {
    // First regex to match numbers with two decimal places or numbers followed by '/-'
    final priceRegExp = RegExp(r'\b\d+\.\d{2}\b|\b\d+/-(?=\s|$)');
    final match = priceRegExp.firstMatch(text);

    if (match != null) {
      print("Price found using first regex: ${match.group(0)}");
      // Clean the extracted value
      return _cleanPrice(match.group(0) ?? "No price found");
    } else {
      // Second regex to match Rs, mrp, ₹, or rp followed by a number
      final fallbackPriceRegExp = RegExp(
          r'\b(?:Rs|mrp|₹|rp)[\s\.:/-]*\d+(\.\d{1,2})?\b(?!\s*(?:[Pp]er\s+\d+|per\s*gram|per\s*g|/g))',
          caseSensitive: false);

      final fallbackMatch = fallbackPriceRegExp.firstMatch(text);

      if (fallbackMatch != null) {
        print("Price found using fallback regex: ${fallbackMatch.group(0)}");
        // Clean the extracted value
        return _cleanPrice(fallbackMatch.group(0) ?? '');
      }
    }

    print("No price found");
    return '';
  }

// Post-processing to clean unwanted characters
  String _cleanPrice(String price) {
    // Remove the currency symbols and prefixes (Rs., MRP., ₹, etc.)
    final cleanPrice = price.replaceAll(
        RegExp(r'^(Rs\.|mrp\.|₹|rp)[\s\.:/-]*', caseSensitive: false), '');

    // Remove any characters like /-, / or anything after the price
    final finalPrice = cleanPrice.replaceAll(RegExp(r'[\s/,-].*$'), '');

    // Return the cleaned numeric price value
    return finalPrice.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          "PRICE EXTRACTOR",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.miniCenterFloat,
      floatingActionButton: FloatingActionButton.large(
        backgroundColor: Colors.green[100],
        child: Icon(
          Icons.camera,
          size: 60,
          color: Colors.green[900],
        ),
        onPressed: _isProcessing ? null : _processImage,
      ),
      body: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.01,
            ),
            Container(
              padding: EdgeInsets.all(10),
              height: MediaQuery.sizeOf(context).height * 0.07,
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
              child: _isProcessing
                  ? CircularProgressIndicator(
                      color: Colors.blueGrey,
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.currency_rupee_outlined, // Currency icon
                          color: _extractedPrice.isEmpty
                              ? Colors.red
                              : Colors.green[800],
                          size: 30,
                        ),
                        SizedBox(width: 5),
                        Text(
                          _extractedPrice.isEmpty
                              ? "No Price found"
                              : _extractedPrice,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: _extractedPrice.isEmpty
                                ? Colors.red
                                : Colors.green[800],
                          ),
                        ),
                      ],
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
            // Text(
            //   "Extracted Price: ",
            //   style: TextStyle(fontSize: 17),
            // ),

            SizedBox(
              height: 20,
            ),
            // MaterialButton(
            //   minWidth: MediaQuery.sizeOf(context).width * 0.5,
            //   height: MediaQuery.sizeOf(context).height * 0.08,
            //   shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(10)),
            //   color: Colors.lightGreenAccent[200],
            //   onPressed: _isProcessing ? null : _processImage,
            //   child: Text(
            //     "Click",
            //     style: TextStyle(fontSize: 25),
            //   ),
            // ),
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
    super.dispose();
  }
}
