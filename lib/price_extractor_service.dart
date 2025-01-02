import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

class PriceExtractorNERApp extends StatefulWidget {
  const PriceExtractorNERApp({super.key});

  @override
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

      // Extract price using your existing logic
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
      String combinedText =
          _extractCombinedText(recognizedText.blocks, priceKeywords);
      print("Combined Text before preprocessing: $combinedText");

      // Preprocess the combined text before extracting price
      String preprocessedText =
          _preprocessTextForEntityExtraction(combinedText);
      print("Preprocessed Combined Text: $preprocessedText");

      // Try extracting price using NER
      String extractedPrice = await _extractPriceUsingNER(preprocessedText);

      // Fallback to regex if NER fails (returns empty string)
      if (extractedPrice.isEmpty) {
        print("NER extraction failed. Falling back to regex.");
        extractedPrice = _extractPriceUsingRegex(preprocessedText);
      }

      print("Extracted Price: $extractedPrice");

      setState(() {
        _extractedPrice = extractedPrice;
      });
    } catch (e) {
      print("Error processing image: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

// Function to extract horizontally or vertically aligned text based on keywords
  String _extractCombinedText(List<TextBlock> blocks, List<String> keywords) {
    Rect? keywordBoundingBox;
    String? keywordText;

    // Create a regular expression from the list of keywords
    final keywordRegex = RegExp(
      r'\b(?:' +
          keywords.map((k) => RegExp.escape(k)).join('|') +
          r')[\.:₹7RZF/-]*\b',
      caseSensitive: false,
    );

    // Find the keyword and its bounding box
    for (TextBlock block in blocks) {
      for (TextLine line in block.lines) {
        if (keywordRegex.hasMatch(line.text)) {
          keywordBoundingBox = line.boundingBox;
          keywordText = line.text;
          print(line.recognizedLanguages);
          break;
        }
      }
      if (keywordBoundingBox != null) break;
    }

    if (keywordBoundingBox == null || keywordText == null) {
      print("No keyword found");
      return '';
    }

    // Function to calculate the distance between two bounding boxes
    double calculateDistance(Rect rect1, Rect rect2) {
      final dx = (rect1.center.dx - rect2.center.dx).abs();
      final dy = (rect1.center.dy - rect2.center.dy).abs();
      return sqrt(dx * dx + dy * dy);
    }

    // Find the closest numeric value to the keyword bounding box in any direction
    String? closestNumericText;
    double closestDistance = double.infinity;

    // Regular expression to match numeric values
    final numericRegex = RegExp(
        r'\b\d+([.,]\d{1,2})?\b'); // Matches numbers like 1000, 1000.50, 1,000.50

    for (TextBlock block in blocks) {
      for (TextLine line in block.lines) {
        Rect lineBoundingBox = line.boundingBox;

        // Skip the keyword itself
        if (lineBoundingBox == keywordBoundingBox) continue;

        // Check if the text contains a numeric value
        if (numericRegex.hasMatch(line.text)) {
          // Calculate the distance between the keyword and the current line
          double distance =
              calculateDistance(keywordBoundingBox, lineBoundingBox);

          // Check if this line is closer than the previous closest line
          if (distance < closestDistance) {
            // Ensure the numeric line is either vertically or horizontally aligned
            if ((lineBoundingBox.center.dx - keywordBoundingBox.center.dx)
                        .abs() <
                    keywordBoundingBox.width ||
                (lineBoundingBox.center.dy - keywordBoundingBox.center.dy)
                        .abs() <
                    keywordBoundingBox.height) {
              closestDistance = distance;
              closestNumericText = line.text;
            }
          }
        }
      }
    }

    if (closestNumericText != null) {
      // Combine the keyword and the closest numeric value into a money-recognizable format
      return "$keywordText $closestNumericText"
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    print("No numeric text found near the keyword");
    return keywordText; // Return only the keyword if no numeric value is found
  }

  String _preprocessTextForEntityExtraction(String text) {
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

    String preprocessedText = text;

    // Loop through each keyword in the list and apply the replacement
    for (var keyword in priceKeywords) {
      // Create a regex pattern to match the keyword followed by optional punctuation marks
      preprocessedText = preprocessedText.replaceAllMapped(
        RegExp(r'\b' + RegExp.escape(keyword) + r'[\.:,;-]?\b',
            caseSensitive: false),
        (match) {
          // Extract the keyword, and replace it with ₹ while preserving the punctuation
          var matchedText = match.group(0)!;
          var replacedText = '₹' +
              matchedText.substring(keyword.length); // Keep punctuation intact
          return replacedText;
        },
      );
    }

    return preprocessedText;
  }

  // Method to extract price using Named Entity Recognition (NER)
  Future<String> _extractPriceUsingNER(String text) async {
    final List<EntityAnnotation> entityAnnotations = await _entityExtractor
        .annotateText(text, entityTypesFilter: [EntityType.money]);

    for (var annotation in entityAnnotations) {
      print("Raw NER Extracted Text: ${annotation.text}");
      // Apply the cleanPrice method to clean the extracted price
      final cleanedPrice = _cleanPrice(annotation.text);
      print("Cleaned NER Extracted Text: $cleanedPrice");
      return cleanedPrice;
    }

    return '';
  }

  //fallback method to extract price
  String _extractPriceUsingRegex(String text) {
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
