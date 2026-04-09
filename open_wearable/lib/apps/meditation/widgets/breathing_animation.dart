import 'dart:math';
import 'package:flutter/material.dart';

/// Breathing animation widget - like Apple Watch breathe app
/// 
/// Shows expanding/contracting circles with smooth transitions
class BreathingAnimation extends StatefulWidget {
  final bool isActive;
  
  const BreathingAnimation({
    super.key,
    required this.isActive,
  });
  
  @override
  State<BreathingAnimation> createState() => _BreathingAnimationState();
}

class _BreathingAnimationState extends State<BreathingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
    
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.5)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);
    
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.3, end: 0.8),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.8, end: 0.3),
        weight: 50,
      ),
    ]).animate(_controller);
    
    if (widget.isActive) {
      _controller.repeat();
    }
  }
  
  @override
  void didUpdateWidget(BreathingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 160,
              width: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _buildPetal(0, _scaleAnimation.value, _opacityAnimation.value),
                  _buildPetal(60, _scaleAnimation.value, _opacityAnimation.value),
                  _buildPetal(120, _scaleAnimation.value, _opacityAnimation.value),
                  _buildPetal(180, _scaleAnimation.value, _opacityAnimation.value),
                  _buildPetal(240, _scaleAnimation.value, _opacityAnimation.value),
                  _buildPetal(300, _scaleAnimation.value, _opacityAnimation.value),
                  
                  Container(
                    width: 50 * _scaleAnimation.value,
                    height: 50 * _scaleAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.blue.withOpacity(0.6),
                          Colors.purple.withOpacity(0.3),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Removed breathe in/out text - just show flower
          ],
        );
      },
    );
  }
  
  Widget _buildPetal(double angle, double scale, double opacity) {
    final radians = angle * pi / 180;
    final distance = 50.0 * scale;
    
    return Transform.translate(
      offset: Offset(
        cos(radians) * distance,
        sin(radians) * distance,
      ),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.blue.withOpacity(opacity * 0.6),
                Colors.purple.withOpacity(opacity * 0.2),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
