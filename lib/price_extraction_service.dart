import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

class PriceExtractionService {
  // Function to extract horizontally or vertically aligned text based on keywords
  String extractCombinedText(List<TextBlock> blocks, List<String> keywords) {
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
          break;
        }
      }
      if (keywordBoundingBox != null) break;
    }

    if (keywordBoundingBox == null || keywordText == null) {
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
    return keywordText; // Return only the keyword if no numeric value is found
  }

  // Preprocess text for entity extraction
  String preprocessTextForEntityExtraction(String text) {
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
          return '₹';
        },
      );
    }
    return preprocessedText;
  }

  // Method to extract price using Named Entity Recognition (NER)
  Future<String> extractPriceUsingNER(
      String text, EntityExtractor entityExtractor) async {
    final List<EntityAnnotation> entityAnnotations = await entityExtractor
        .annotateText(text, entityTypesFilter: [EntityType.money]);
    for (var annotation in entityAnnotations) {
      return cleanPrice(annotation.text);
    }
    return '';
  }

  // Fallback method to extract price using Regex
  String extractPriceUsingRegex(String text) {
    final priceRegExp = RegExp(r'\b\d+\.\d{2}\b|\b\d+/(?=\s|$)');
    final match = priceRegExp.firstMatch(text);

    if (match != null) {
      return cleanPrice(match.group(0) ?? '');
    } else {
      final fallbackPriceRegExp = RegExp(
          r'\b(?:Rs|mrp|₹|rp)[\s\.:/-]*\d+(\.\d{1,2})?\b',
          caseSensitive: false);

      final fallbackMatch = fallbackPriceRegExp.firstMatch(text);

      if (fallbackMatch != null) {
        return cleanPrice(fallbackMatch.group(0) ?? '');
      }
    }

    return '';
  }

  // Clean unwanted characters from price text
  String cleanPrice(String price) {
    // Remove any prefix like Rs., ₹, rp, etc.
    final cleanPrice = price.replaceAll(
        RegExp(r'^(Rs\.|mrp\.|₹|rp)[\s\.:/-]*', caseSensitive: false), '');

    // Remove commas, spaces, and unwanted characters from both ends
    final finalPrice = cleanPrice.replaceAll(RegExp(r'[^\d\.,]'), '');

    return finalPrice.trim();
  }
}
