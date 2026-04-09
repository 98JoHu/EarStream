import 'package:flutter/material.dart';

/// Cute animated timer widget that shows progress with dancing elements
class CuteTimerWidget extends StatefulWidget {
  final int currentSeconds;
  final int totalSeconds;
  final String label;
  
  const CuteTimerWidget({
    super.key,
    required this.currentSeconds,
    required this.totalSeconds,
    this.label = 'Collecting data',
  });
  
  @override
  State<CuteTimerWidget> createState() => _CuteTimerWidgetState();
}

class _CuteTimerWidgetState extends State<CuteTimerWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _messageController;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Pulsing heart animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Wave animation for background
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    // Message rotation animation (slower - every 5 seconds)
    _messageController = AnimationController(
      duration: const Duration(seconds: 20), // 5 seconds per message x 4 messages
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _messageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final progress = widget.currentSeconds / widget.totalSeconds;
    final remainingMinutes = ((widget.totalSeconds - widget.currentSeconds) / 60).floor();
    final remainingSeconds = (widget.totalSeconds - widget.currentSeconds) % 60;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF3E5F5).withOpacity(0.3),
            const Color(0xFFE1BEE7).withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF9C27B0).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Animated icon with pulse
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Icon(
                  Icons.favorite,
                  size: 32,
                  color: Color.lerp(
                    const Color(0xFF9C27B0),
                    const Color(0xFFE91E63),
                    (_pulseController.value),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          
          // Progress bar with wave animation
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFF9C27B0),
                            const Color(0xFFE91E63),
                            const Color(0xFF9C27B0),
                          ],
                          stops: [
                            0.0,
                            _waveController.value,
                            1.0,
                          ],
                        ).createShader(bounds);
                      },
                      child: Container(
                        height: 6,
                        width: MediaQuery.of(context).size.width * progress,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Time remaining
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  key: ValueKey('$remainingMinutes:$remainingSeconds'),
                  '${remainingMinutes}:${remainingSeconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11,
                    color: const Color(0xFF9C27B0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          // Cute encouraging text
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _messageController,
            builder: (context, child) {
              final texts = [
                '💜 Keep breathing...',
                '✨ Almost there!',
                '🌟 Stay calm...',
                '💫 You\'re doing great!',
              ];
              final index = (_messageController.value * 4).floor() % texts.length;
              
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Text(
                  texts[index],
                  key: ValueKey(texts[index]),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
