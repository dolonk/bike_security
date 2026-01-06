import 'package:flutter/material.dart';

/// Reusable control button widget for bike controls
class ControlButton extends StatelessWidget {
  final String label;
  final String command;
  final Color color;
  final double height;
  final VoidCallback onPressed;

  const ControlButton({
    super.key,
    required this.label,
    required this.command,
    required this.color,
    required this.onPressed,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: Size(100, height)),
          onPressed: onPressed,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
