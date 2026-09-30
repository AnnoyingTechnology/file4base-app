import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class IssuesGuideDialog extends StatelessWidget {
  const IssuesGuideDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const IssuesGuideDialog(),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.10),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E88E5).withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.help_outline_rounded,
                        color: Color(0xFF1E88E5),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Service & Support — GitHub Issues',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Guía de buenas prácticas antes de abrir un ticket o incidencia',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
              ),

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF1E88E5).withValues(alpha: 0.20),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF1E88E5), size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'El seguimiento de incidencias, errores y peticiones de características '
                                'se gestiona públicamente en el repositorio GitHub de File4Base.',
                                style: TextStyle(fontSize: 12, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Pautas para trabajar con Issues:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _buildGuidelineRow(
                        context,
                        icon: Icons.search_rounded,
                        title: '1. Busca incidencias existentes',
                        description:
                            'Comprueba si el problema ya ha sido reportado previamente para evitar tickets duplicados y unificar la discusión.',
                      ),
                      const SizedBox(height: 10),
                      _buildGuidelineRow(
                        context,
                        icon: Icons.title_rounded,
                        title: '2. Título claro con etiqueta',
                        description:
                            'Utiliza prefijos descriptivos como [Bug], [Feature], [Desktop] o [WebDirect] (ej: "[Bug] Error al conectar con PostgreSQL").',
                      ),
                      const SizedBox(height: 10),
                      _buildGuidelineRow(
                        context,
                        icon: Icons.format_list_numbered_rounded,
                        title: '3. Pasos exactos para reproducir',
                        description:
                            'Detalla paso a paso qué acciones causan el comportamiento inesperado y cuál era el resultado esperado.',
                      ),
                      const SizedBox(height: 10),
                      _buildGuidelineRow(
                        context,
                        icon: Icons.devices_rounded,
                        title: '4. Datos de entorno y logs',
                        description:
                            'Indica tu versión de File4Base (v0.4.18), sistema operativo (macOS, Windows, Linux, Web) y logs del contenedor si aplica.',
                      ),
                      const SizedBox(height: 10),
                      _buildGuidelineRow(
                        context,
                        icon: Icons.security_rounded,
                        title: '5. Privacidad y credenciales',
                        description:
                            'Nunca incluyas contraseñas reales, tokens ni datos confidenciales en los logs o capturas de pantalla adjuntas.',
                      ),
                    ],
                  ),
                ),
              ),

              // Footer Button Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(
                    top: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        _openUrl('https://github.com/file4base/file4base-app/issues');
                      },
                      icon: const Icon(Icons.search, size: 15),
                      label: const Text('Ver Issues Existentes', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _openUrl('https://github.com/file4base/file4base-app/issues/new/choose');
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 15),
                          label: const Text('Ir a GitHub Issues', style: TextStyle(fontSize: 12)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidelineRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF1E88E5)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
