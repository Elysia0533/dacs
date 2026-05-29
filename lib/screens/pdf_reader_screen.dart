import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:io';
import '../models/story.dart';

import '../services/google_drive_service.dart';

class PdfReaderScreen extends StatelessWidget {
  final Story story;

  const PdfReaderScreen({super.key, required this.story});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(story.title),
      ),
      body: story.isFromDrive && story.localPath.isEmpty
          ? SfPdfViewer.network(
              GoogleDriveService.getDownloadUrl(story.driveFileId),
              canShowScrollHead: false,
              canShowScrollStatus: false,
            )
          : SfPdfViewer.file(
              File(story.localPath),
              canShowScrollHead: false,
              canShowScrollStatus: false,
            ),
    );
  }
}
