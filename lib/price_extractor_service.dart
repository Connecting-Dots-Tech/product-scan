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
      String nerPrice = await _extractPriceUsingNER(recognizedText.text);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Price Extractor"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
        child: Column(
          children: [
            if (_isCameraInitialized)
              Expanded(child: Center(child: CameraPreview(_cameraController))),
            Text(
              "Extracted Price: ",
              style: TextStyle(fontSize: 17),
            ),
            Text(
              _extractedPrice,
              style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800]),
            ),
            SizedBox(
              height: 20,
            ),
            MaterialButton(
              minWidth: MediaQuery.sizeOf(context).width * 0.5,
              height: 80,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              color: Colors.lightGreenAccent[200],
              onPressed: _isProcessing ? null : _processImage,
              child: Text(
                "Click",
                style: TextStyle(fontSize: 25),
              ),
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
    super.dispose();
  }
}
