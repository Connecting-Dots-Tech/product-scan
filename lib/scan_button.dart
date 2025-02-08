import 'package:flutter/material.dart';
import 'package:price_snap/price_extractor.dart';

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product Scanner')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            // Navigate to the scanning page
            final product = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PriceExtractorApp(
                  url: 'http://192.168.43.223:4001/products/barcode/',
                ),
              ),
            );

            if (product != null) {
              // Display product details
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Product: ${product.name}')),
              );
            }
          },
          child: const Text('Scan Product'),
        ),
      ),
    );
  }
}
