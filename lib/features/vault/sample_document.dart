import 'dart:convert';
import 'dart:typed_data';

/// A small, valid PDF generated in the app.
///
/// This build has no camera or file picker, so there is no way to hand
/// FynnVault a file from the device. Rather than a button that pretends to
/// pick one, the vault can store this: a real document, really uploaded,
/// really retrievable — and named so nobody mistakes it for something the
/// customer scanned.
class SampleDocument {
  const SampleDocument._();

  static const String fileName = 'FynnEdge sample document.pdf';
  static const String mimeType = 'application/pdf';

  /// A minimal one-page PDF. Small enough to hold in memory, complete enough
  /// that a viewer will open it and the server will detect its type.
  static Uint8List bytes({String title = 'FynnEdge sample document'}) {
    final text = title.replaceAll('(', '').replaceAll(')', '');

    final content =
        'BT /F1 16 Tf 60 720 Td ($text) Tj ET\n'
        'BT /F1 11 Tf 60 690 Td (Stored in FynnVault. Nothing has been '
        'verified or shared.) Tj ET';

    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];

    for (var i = 0; i < objects.length; i++) {
      offsets.add(buffer.length);
      buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }

    final xrefStart = buffer.length;
    buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefStart\n%%EOF\n',
    );

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }
}
