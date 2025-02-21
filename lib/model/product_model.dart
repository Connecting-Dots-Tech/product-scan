class ProductModel {
  ProductModel({
    this.code,
    this.name,
    this.category,
    this.brand,
    this.productCode,
    this.salesPrice,
    this.bmrp,
    this.discount,
    this.barcode,
  });

  ProductModel.fromJson(dynamic json) {
    code = json['code'];
    name = json['name'];
    category = json['category'];
    brand = json['brand'];
    productCode = json['productCode'];
    // Handle different types for salesPrice
    if (json['salesPrice'] != null) {
      if (json['salesPrice'] is int) {
        salesPrice = (json['salesPrice'] as int).toDouble();
      } else if (json['salesPrice'] is double) {
        salesPrice = json['salesPrice'];
      }
    }
    if (json['bmrp'] != null) {
      if (json['bmrp'] is int) {
        bmrp = (json['bmrp'] as int).toDouble();
      } else if (json['bmrp'] is double) {
        bmrp = json['bmrp'];
      }
    }
    if (json['discount'] != null) {
      if (json['discount'] is int) {
        discount = (json['discount'] as int).toDouble();
      } else if (json['discount'] is double) {
        discount = json['discount'];
      }
    }
    barcode = json['barcode'];
  }

  String? code;
  String? name;
  String? category;
  String? brand;
  String? productCode;
  double? salesPrice;
  double? discount;
  double? bmrp;
  String? barcode;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['code'] = code;
    map['name'] = name;
    map['category'] = category;
    map['brand'] = brand;
    map['productCode'] = productCode;
    map['salesPrice'] = salesPrice;
    map['barcode'] = barcode;
    map['bmrp'] = bmrp;
    map['discount'] = discount;
    return map;
  }
}
