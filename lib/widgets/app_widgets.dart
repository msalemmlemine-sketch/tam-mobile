import 'package:flutter/material.dart';

class AppSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const AppSection({super.key, required this.title, this.subtitle, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)],
      ])),
      if (trailing != null) trailing!,
    ])),
    child,
  ]);
}

class MetricCard extends StatelessWidget {
  final IconData icon; final String label; final String value; final String? caption; final VoidCallback? onTap;
  const MetricCard({super.key, required this.icon, required this.label, required this.value, this.caption, this.onTap});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: scheme.onPrimaryContainer)),
      const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (caption != null) Text(caption!, style: Theme.of(context).textTheme.labelSmall),
      ])),
    ]))));
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon; final String title; final String? subtitle; final Widget? action;
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle), child: Icon(icon, size: 38, color: scheme.onPrimaryContainer)),
      const SizedBox(height: 16), Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)],
      if (action != null) ...[const SizedBox(height: 18), action!],
    ])));
  }
}

class StatusChip extends StatelessWidget {
  final String status; const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme; final active = status == 'active'; final suspended = status == 'suspended';
    final bg = active ? scheme.primaryContainer : suspended ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = active ? scheme.onPrimaryContainer : suspended ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    final text = active ? 'نشط' : suspended ? 'موقوف' : 'غير نشط';
    return Chip(label: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)), backgroundColor: bg, side: BorderSide.none, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero);
  }
}
