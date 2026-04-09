import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'cute_timer_widget.dart';

class HrHrvChart extends StatefulWidget {
  final Stream<double> hrStream;
  final Stream<Map<String, double>> hrvStream;
  final List<double> initialHrData;
  final List<double> initialHrvData;
  final int? measurementDurationSeconds; // For SDNN timer

  const HrHrvChart({
    super.key,
    required this.hrStream,
    required this.hrvStream,
    this.initialHrData = const [],
    this.initialHrvData = const [],
    this.measurementDurationSeconds,
  });

  @override
  State<HrHrvChart> createState() => _HrHrvChartState();
}

class _HrHrvChartState extends State<HrHrvChart> with SingleTickerProviderStateMixin {
  final List<double> _hrHistory = [];
  final List<double> _hrvRmssdHistory = [];
  final List<double> _hrvSdnnHistory = [];
  final int _maxDataPoints = 3600; // Keep up to 1 hour of data (~1 data point per second)
  
  double _currentHr = 75.0;
  double _currentHrvRmssd = -1.0; // -1 means no data yet
  double _currentHrvSdnn = -1.0;  // -1 means no data yet
  
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  
  late AnimationController _heartBeatController;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize history with provided data (RMSSD)
    if (widget.initialHrData.isNotEmpty) {
      _hrHistory.addAll(widget.initialHrData);
      _currentHr = widget.initialHrData.last;
    }
    if (widget.initialHrvData.isNotEmpty) {
      _hrvRmssdHistory.addAll(widget.initialHrvData);
      _currentHrvRmssd = widget.initialHrvData.last;
      // Estimate SDNN from RMSSD (roughly 2.7x smaller)
      _hrvSdnnHistory.addAll(widget.initialHrvData.map((rmssd) => rmssd / 2.7));
      _currentHrvSdnn = _hrvSdnnHistory.last;
    }
    
    _heartBeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Start repeating animation
    _heartBeatController.repeat();
    
    _hrSubscription = widget.hrStream.listen((hr) {
      setState(() {
        _currentHr = hr;
        _hrHistory.add(hr);
        if (_hrHistory.length > _maxDataPoints) {
          _hrHistory.removeAt(0);
        }
      });
      
      // Update animation speed based on heart rate
      final bpm = hr.clamp(40.0, 200.0);
      final durationMs = (60000 / bpm).round();
      _heartBeatController.duration = Duration(milliseconds: durationMs);
    });
    
    _hrvSubscription = widget.hrvStream.listen((hrv) {
      final rmssd = hrv['HRV_RMSSD'] ?? 120.0;
      final sdnn = hrv['HRV_SDNN'] ?? 44.0;
      setState(() {
        _currentHrvRmssd = rmssd;
        _currentHrvSdnn = sdnn;
        _hrvRmssdHistory.add(rmssd);
        _hrvSdnnHistory.add(sdnn);
        if (_hrvRmssdHistory.length > _maxDataPoints) {
          _hrvRmssdHistory.removeAt(0);
        }
        if (_hrvSdnnHistory.length > _maxDataPoints) {
          _hrvSdnnHistory.removeAt(0);
        }
      });
    });
  }
  
  @override
  void dispose() {
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _heartBeatController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Live Heart Data'),
        material: (_, __) => MaterialAppBarData(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Animated Heart with Current HR
                _buildAnimatedHeartSection(),
                
                const SizedBox(height: 24),
                
                // Current Values Card
                _buildCurrentValuesCard(),
                
                const SizedBox(height: 24),
                
                // HR Chart
                _buildChartCard(
                  title: 'Heart Rate (BPM)',
                  data: _hrHistory,
                  color: Colors.red,
                  minValue: 50.0,
                  maxValue: 120.0,
                  icon: Icons.favorite,
                ),
                
                const SizedBox(height: 16),
                
                // HRV RMSSD Chart or Timer
                _currentHrvRmssd < 0
                    ? _buildRmssdTimerCard()
                    : _buildChartCard(
                        title: 'HRV RMSSD (ms)',
                        data: _hrvRmssdHistory,
                        color: const Color(0xFF4ECDC4),
                        minValue: 0.0,
                        maxValue: 200.0,
                        icon: Icons.show_chart,
                      ),
                
                const SizedBox(height: 16),
                
                // HRV SDNN Chart or Timer
                _currentHrvSdnn < 0
                    ? _buildSdnnTimerCard()
                    : _buildChartCard(
                        title: 'HRV SDNN (ms)',
                        data: _hrvSdnnHistory,
                        color: const Color(0xFF9C27B0),
                        minValue: 0.0,
                        maxValue: 80.0,
                        icon: Icons.timeline,
                      ),
                
                const SizedBox(height: 24),
                
                // Close Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAnimatedHeartSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Animated Heart Icon
            AnimatedBuilder(
              animation: _heartBeatController,
              builder: (context, child) {
                final scale = 1.0 + (_heartBeatController.value * 0.3);
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    Icons.favorite,
                    size: 80,
                    color: Color.lerp(
                      Colors.red[300],
                      Colors.red[700],
                      _heartBeatController.value,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              '${_currentHr.toStringAsFixed(0)} BPM',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6366F1),
              ),
            ),
            const Text(
              'Current Heart Rate',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCurrentValuesCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                icon: Icons.favorite,
                label: 'Heart Rate',
                value: '${_currentHr.toStringAsFixed(0)} BPM',
                color: Colors.red,
              ),
            ),
            Container(
              width: 1,
              height: 60,
              color: Colors.grey[300],
            ),
            Expanded(
              child: _buildStatItem(
                icon: Icons.show_chart,
                label: 'RMSSD',
                value: _currentHrvRmssd < 0 ? 'Loading...' : '${_currentHrvRmssd.toStringAsFixed(1)} ms',
                color: const Color(0xFF4ECDC4),
              ),
            ),
            Container(
              width: 1,
              height: 60,
              color: Colors.grey[300],
            ),
            Expanded(
              child: _buildStatItem(
                icon: Icons.timeline,
                label: 'SDNN',
                value: _currentHrvSdnn < 0 ? 'Loading...' : '${_currentHrvSdnn.toStringAsFixed(1)} ms',
                color: const Color(0xFF9C27B0),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  Widget _buildSdnnTimerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: const Color(0xFF9C27B0), size: 24),
                const SizedBox(width: 8),
                const Text(
                  'HRV SDNN (ms)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CuteTimerWidget(
              currentSeconds: widget.measurementDurationSeconds ?? 0,
              totalSeconds: 300, // 5 minutes
              label: 'Collecting data for SDNN',
            ),
            const SizedBox(height: 16),
            Text(
              'SDNN requires at least 5 minutes of continuous measurement for accurate results.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRmssdTimerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: const Color(0xFF4ECDC4), size: 24),
                const SizedBox(width: 8),
                const Text(
                  'HRV RMSSD (ms)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CuteTimerWidget(
              currentSeconds: widget.measurementDurationSeconds ?? 0,
              totalSeconds: 20, // 20 seconds for RMSSD
              label: 'Collecting data for RMSSD',
            ),
            const SizedBox(height: 16),
            Text(
              'RMSSD requires at least 20 seconds of continuous measurement for accurate results.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildChartCard({
    required String title,
    required List<double> data,
    required Color color,
    required double minValue,
    required double maxValue,
    required IconData icon,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200, // Increased height for better visibility
              child: data.isEmpty
                  ? Center(
                      child: Text(
                        'Collecting data...',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : CustomPaint(
                      painter: LineChartPainter(
                        data: data,
                        color: color,
                        minValue: minValue,
                        maxValue: maxValue,
                        showYAxis: true, // Show Y-axis labels
                      ),
                      size: Size.infinite,
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: ${data.isEmpty ? "--" : data.reduce(min).toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  'Max: ${data.isEmpty ? "--" : data.reduce(max).toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  'Avg: ${data.isEmpty ? "--" : (data.reduce((a, b) => a + b) / data.length).toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double minValue;
  final double maxValue;
  final bool showYAxis;

  LineChartPainter({
    required this.data,
    required this.color,
    required this.minValue,
    required this.maxValue,
    this.showYAxis = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.3),
          color.withOpacity(0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1).clamp(1, double.infinity);
    
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = ((data[i] - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
      final y = size.height - (normalizedValue * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete the fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw fill
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    canvas.drawPath(path, paint);

    // Draw dots
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = ((data[i] - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
      final y = size.height - (normalizedValue * size.height);

      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

/// Dual-axis chart painter for displaying HR and HRV on same timeline
class DualAxisChartPainter extends CustomPainter {
  final List<double> hrData;
  final List<double> hrvData;
  final Color hrColor;
  final Color hrvColor;

  DualAxisChartPainter({
    required this.hrData,
    required this.hrvData,
    required this.hrColor,
    required this.hrvColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 0.5;
    
    for (int i = 0; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(40, y), Offset(size.width, y), gridPaint);
    }
    
    final chartWidth = size.width - 80; // Leave space for Y-axis labels
    final maxDataPoints = max(hrData.length, hrvData.length);
    if (maxDataPoints == 0) return;
    
    // Calculate ranges
    final hrMin = hrData.isEmpty ? 40.0 : hrData.reduce(min);
    final hrMax = hrData.isEmpty ? 120.0 : hrData.reduce(max);
    final hrRange = (hrMax - hrMin).clamp(10.0, double.infinity);
    
    final hrvMin = hrvData.isEmpty ? 0.0 : hrvData.reduce(min);
    final hrvMax = hrvData.isEmpty ? 100.0 : hrvData.reduce(max);
    final hrvRange = (hrvMax - hrvMin).clamp(10.0, double.infinity);
    
    // Draw HR line (left Y-axis)
    if (hrData.isNotEmpty) {
      final hrPaint = Paint()
        ..color = hrColor.withOpacity(0.8)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      final hrPath = Path();
      final stepX = chartWidth / (hrData.length - 1).clamp(1, double.infinity);
      
      for (int i = 0; i < hrData.length; i++) {
        final x = 40 + (i * stepX);
        final normalizedValue = ((hrData[i] - hrMin) / hrRange).clamp(0.0, 1.0);
        final y = size.height - (normalizedValue * size.height);
        
        if (i == 0) {
          hrPath.moveTo(x, y);
        } else {
          hrPath.lineTo(x, y);
        }
      }
      
      canvas.drawPath(hrPath, hrPaint);
    }
    
    // Draw HRV line (right Y-axis)
    if (hrvData.isNotEmpty) {
      final hrvPaint = Paint()
        ..color = hrvColor.withOpacity(0.8)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      final hrvPath = Path();
      final stepX = chartWidth / (hrvData.length - 1).clamp(1, double.infinity);
      
      for (int i = 0; i < hrvData.length; i++) {
        final x = 40 + (i * stepX);
        final normalizedValue = ((hrvData[i] - hrvMin) / hrvRange).clamp(0.0, 1.0);
        final y = size.height - (normalizedValue * size.height);
        
        if (i == 0) {
          hrvPath.moveTo(x, y);
        } else {
          hrvPath.lineTo(x, y);
        }
      }
      
      canvas.drawPath(hrvPath, hrvPaint);
    }
    
    // Draw Y-axis labels for HR (left)
    if (hrData.isNotEmpty) {
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      );
      
      for (int i = 0; i <= 4; i++) {
        final value = hrMin + (hrRange * i / 4);
        textPainter.text = TextSpan(
          text: value.toStringAsFixed(0),
          style: TextStyle(color: hrColor, fontSize: 10),
        );
        textPainter.layout();
        final y = size.height - (size.height * i / 4) - 6;
        textPainter.paint(canvas, Offset(2, y));
      }
    }
    
    // Draw Y-axis labels for HRV (right)
    if (hrvData.isNotEmpty) {
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      
      for (int i = 0; i <= 4; i++) {
        final value = hrvMin + (hrvRange * i / 4);
        textPainter.text = TextSpan(
          text: value.toStringAsFixed(0),
          style: TextStyle(color: hrvColor, fontSize: 10),
        );
        textPainter.layout();
        final y = size.height - (size.height * i / 4) - 6;
        textPainter.paint(canvas, Offset(size.width - 35, y));
      }
    }
  }

  @override
  bool shouldRepaint(DualAxisChartPainter oldDelegate) {
    return oldDelegate.hrData != hrData || oldDelegate.hrvData != hrvData;
  }
}
