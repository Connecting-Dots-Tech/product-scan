import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:price_snap/api_service.dart';

class ProductDetailsPage extends StatefulWidget {
  final ProductModel product;

  const ProductDetailsPage({Key? key, required this.product}) : super(key: key);

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("Product Details"),
          centerTitle: true,
          leading: BackButton(
            onPressed: () {
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductInfo(
                label: "Name",
                value: '${widget.product.name}',
                isTitle: true,
              ),
              const SizedBox(height: 16),
              _buildProductInfo(
                label: "Price",
                value: "${widget.product.brand}",
              ),
              const SizedBox(height: 12),
              _buildProductInfo(
                label: "Sales Price",
                value: "₹${widget.product.salesPrice}",
              ),
              const SizedBox(height: 12),
              _buildProductInfo(
                label: "MRP",
                value: "₹${widget.product.bmrp}",
              ),
            ],
          ),
        ));
  }

  Widget _buildProductInfo({
    required String label,
    required String value,
    bool isTitle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isTitle ? 20 : 18,
              fontWeight: isTitle ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
