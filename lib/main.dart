import 'package:flutter/material.dart';
import 'package:price_snap/price_extraction_service.dart';
import 'package:price_snap/price_extractor.dart';
import 'package:price_snap/pricechecker_api_service.dart';
import 'package:price_snap/scanner_widget.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Price Extractor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      debugShowCheckedModeBanner: false,
      home: const PriceExtractorNERApp(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize your services
    final apiService = ApiService();
    final priceExtractionService = PriceExtractionService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price Snap'),
      ),
      body: ScannerWidget(
        apiService: apiService,
        priceExtractionService: priceExtractionService,
      ),
    );
  }
}
