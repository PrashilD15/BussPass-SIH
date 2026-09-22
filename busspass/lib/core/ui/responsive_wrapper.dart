import 'package:flutter/material.dart';

/// A wrapper widget that constrains its child's width on large screens (e.g., web or tablets).
/// It creates a mobile-like centered layout, which prevents UI elements from stretching infinitely.
class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color? backgroundColor;
  
  const ResponsiveWrapper({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > maxWidth) {
          // Large screen layout: Center and constrain width
          return Container(
            color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                ),
                child: Container(
                  // Optional: add a subtle border or shadow to mimic a device screen
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: ClipRect(child: child),
                ),
              ),
            ),
          );
        }
        
        // Mobile layout: take full width
        return Container(
          color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
          child: child,
        );
      },
    );
  }
}
