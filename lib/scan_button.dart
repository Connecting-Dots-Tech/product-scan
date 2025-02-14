import 'package:flutter/material.dart';
import 'package:price_snap/api_service.dart';
import 'package:price_snap/product_details_page.dart';
import 'package:price_snap/product_scanner.dart';

class ScanButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Product Scanner Button')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            // Navigate to the scanning page
            final product = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PriceExtractorApp(
                  url: 'http://192.168.106.11:4001/products/barcode/',
                  onResult: (ProductModel? product) {
                    if (product != null) {
                      // Display product details
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProductDetailsPage(product: product),
                          ));
                    }
                  },
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
          child: Text(
            'SCAN',
            style: TextStyle(fontSize: 50, color: Colors.green[900]),
          ),
        ),
      ),
    );
  }
}
