import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  _BarcodeScannerPageState createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  String _scanResult = 'No barcode detected';
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _isCameraInitialized = false;
  bool _isCameraPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _requestCameraPermission();
    await _initializeCamera();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _isCameraPermissionGranted = status == PermissionStatus.granted;
    });
  }

  Future<void> _initializeCamera() async {
    if (!_isCameraPermissionGranted) return;

    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras[0],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
        );

        await _cameraController!.initialize();

        if (!mounted) return;

        await _cameraController!.startImageStream((CameraImage image) {
          if (_isCameraInitialized) {
            _processImage(image);
          }
        });

        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Camera initialization error: $e');
      }
    }
  }

  Future<void> _processImage(CameraImage image) async {
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
        setState(() {
          _scanResult = barcodes.first.displayValue ?? 'Barcode detected';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Barcode scanning error: $e');
      }
    }
  }

  InputImageRotation _getCameraRotation() {
    final deviceRotation = _cameraController!.description.sensorOrientation;
    if (deviceRotation == 90) return InputImageRotation.rotation90deg;
    if (deviceRotation == 180) return InputImageRotation.rotation180deg;
    if (deviceRotation == 270) return InputImageRotation.rotation270deg;
    return InputImageRotation.rotation0deg;
  }

  // @override
  // void didChangeAppLifecycleState(AppLifecycleState state) {
  //   if (!_isCameraInitialized) return;

  //   if (state == AppLifecycleState.inactive) {
  //     _cameraController?.stopImageStream();
  //   } else if (state == AppLifecycleState.resumed) {
  //     _initializeCamera();
  //   }
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();

    if (_cameraController != null) {
      _cameraController?.dispose();
    }

    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode Scanner')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildCameraPreview(),
          const SizedBox(height: 20),
          Text(
            'Scan Result: $_scanResult',
            style: const TextStyle(fontSize: 18),
          ),
          ElevatedButton(
            onPressed: _initializeCamera,
            child: const Text('Restart Scanner'),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraPermissionGranted) {
      return const Text('Camera permission not granted');
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const CircularProgressIndicator();
    }

    return AspectRatio(
        aspectRatio: 2 / 2.9, child: CameraPreview(_cameraController!));
  }
}
