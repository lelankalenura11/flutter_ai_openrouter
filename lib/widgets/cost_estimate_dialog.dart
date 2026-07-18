import 'package:flutter/material.dart';

/// Shows an estimated token/cost preview before sending expensive multimodal
/// inputs (video frames, scanned PDFs) so the user isn't surprised by API cost.
///
/// Called from the send pipeline when the estimated cost exceeds a threshold.
class CostEstimateDialog extends StatelessWidget {
  final int estimatedTokens;
  final int frameCount;
  final String description;

  const CostEstimateDialog({
    super.key,
    required this.estimatedTokens,
    required this.frameCount,
    this.description = 'video',
  });

  /// Computed fields
  double get _estimatedCostUsd {
    // Very rough estimate: GPT-4o vision is ~$2.50/1M input tokens
    // This is an approximation; actual cost depends on the model.
    return (estimatedTokens / 1_000_000) * 2.50;
  }

  String get _formattedCost {
    if (_estimatedCostUsd < 0.01) return '< \$0.01';
    return '\$${_estimatedCostUsd.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Cost Estimate'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This $description contains $frameCount frame${frameCount == 1 ? '' : 's'} '
            'that will be sent to the vision model.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _buildInfoRow(context, 'Estimated tokens', '~${estimatedTokens.toStringAsFixed(0)}'),
          const SizedBox(height: 4),
          _buildInfoRow(context, 'Est. cost', _formattedCost),
          const SizedBox(height: 4),
          _buildInfoRow(context, 'Model', 'Current model'),
          const SizedBox(height: 16),
          Text(
            'Actual cost may vary based on image resolution and the model\'s pricing.',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Send Anyway'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}