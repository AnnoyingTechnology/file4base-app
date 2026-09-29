import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../main.dart';
import 'field_options_dialog.dart';

import 'widgets/relationship_graph_widget.dart';

class ManageDatabaseDialog extends ConsumerStatefulWidget {
  const ManageDatabaseDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const ManageDatabaseDialog(),
    );
  }

  @override
  ConsumerState<ManageDatabaseDialog> createState() => _ManageDatabaseDialogState();
}

class _ManageDatabaseDialogState extends ConsumerState<ManageDatabaseDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TableModel> _tables = [];
  List<TableOccurrenceModel> _occurrences = [];
  List<RelationshipModel> _relationships = [];
  TableModel? _selectedTable;
  bool _isLoading = true;
  String? _errorMessage;
  String _tableSearchFilter = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTables();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = ref.read(apiClientProvider);
    try {
      final tables = await client.listTables();
      final occurrences = await client.listOccurrences();
      final relationships = await client.listRelationships();
      if (mounted) {
        setState(() {
          _tables = tables;
          _occurrences = occurrences;
          _relationships = relationships;
          if (_selectedTable != null) {
            _selectedTable = tables.firstWhere(
              (t) => t.id == _selectedTable!.id,
              orElse: () => tables.isNotEmpty ? tables.first : _selectedTable!,
            );
          } else if (tables.isNotEmpty) {
            _selectedTable = tables.first;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showNewTableDialog() async {
    final nameController = TextEditingController();
    final customNameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name (e.g. Customers)',
                hintText: 'Human readable name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customNameController,
              decoration: const InputDecoration(
                labelText: 'SQL Name (Optional, e.g. customers)',
                hintText: 'Defaults to snake_case',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final disp = nameController.text.trim();
              if (disp.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final client = ref.read(apiClientProvider);
                final newTbl = await client.createTable(
                  disp,
                  customName: customNameController.text.trim(),
                );
                _selectedTable = newTbl;
                await _loadTables();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating table: $e')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showNewFieldDialog() async {
    if (_selectedTable == null) return;
    final nameController = TextEditingController();
    final dispController = TextEditingController();
    String selectedType = 'TEXT';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('New Field for "${_selectedTable!.displayName}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dispController,
                decoration: const InputDecoration(
                  labelText: 'Field Label (e.g. Phone Number)',
                ),
                autofocus: true,
                onChanged: (val) {
                  if (nameController.text.isEmpty ||
                      nameController.text == val.toLowerCase().replaceAll(' ', '_')) {
                    nameController.text = val.toLowerCase().replaceAll(' ', '_');
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Column Name (e.g. phone_number)',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Field Type'),
                items: const [
                  DropdownMenuItem(value: 'TEXT', child: Text('Text')),
                  DropdownMenuItem(value: 'NUMBER', child: Text('Number')),
                  DropdownMenuItem(value: 'DATE', child: Text('Date')),
                  DropdownMenuItem(value: 'TIMESTAMP', child: Text('Timestamp')),
                  DropdownMenuItem(value: 'BOOLEAN', child: Text('Boolean')),
                  DropdownMenuItem(value: 'CONTAINER', child: Text('Container (Blob/Files)')),
                  DropdownMenuItem(value: 'CALCULATION', child: Text('Calculation')),
                  DropdownMenuItem(value: 'SUMMARY', child: Text('Summary')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedType = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final disp = dispController.text.trim();
                if (name.isEmpty || disp.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final client = ref.read(apiClientProvider);
                  await client.addColumn(
                    _selectedTable!.id,
                    name: name,
                    displayName: disp,
                    fieldType: selectedType,
                  );
                  await _loadTables();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding field: $e')),
                    );
                  }
                }
              },
              child: const Text('Add Field'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFieldOptionsDialog(ColumnModel col) async {
    if (_selectedTable == null) return;
    final updated = await FieldOptionsDialog.show(
      context,
      table: _selectedTable!,
      column: col,
    );
    if (updated != null) {
      await _loadTables();
    }
  }

  Future<void> _showEditFieldDialog(ColumnModel col) async {
    final dispController = TextEditingController(text: col.displayName);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Field "${col.displayName}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SQL Identifier: ${col.name}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: dispController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Display Name / Label',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newDisp = dispController.text.trim();
              if (newDisp.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final client = ref.read(apiClientProvider);
                await client.updateColumn(_selectedTable!.id, col.id, displayName: newDisp);
                await _loadTables();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating field: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteFieldDialog(ColumnModel col) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Field "${col.displayName}"?'),
        content: Text('Are you sure you want to drop column "${col.name}" from table "${_selectedTable!.displayName}"? All data stored in this column will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Field'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final client = ref.read(apiClientProvider);
        await client.deleteColumn(_selectedTable!.id, col.id);
        await _loadTables();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting field: $e')),
          );
        }
      }
    }
  }

  // ─── Table-level action dialogs ──────────────────────────────────────────

  Future<void> _showRenameTableDialog(TableModel tbl) async {
    final ctrl = TextEditingController(text: tbl.displayName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SQL name (unchanged): ${tbl.name}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final client = ref.read(apiClientProvider);
                await client.renameTable(tbl.id, newName);
                await _loadTables();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error renaming table: $e')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDuplicateTableDialog(TableModel tbl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicate Table'),
        content: Text(
          'This will create a copy of "${tbl.displayName}" with all its field definitions (no data). Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final client = ref.read(apiClientProvider);
      await client.duplicateTable(tbl.id);
      await _loadTables();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error duplicating table: $e')),
        );
      }
    }
  }

  Future<void> _showTruncateTableDialog(TableModel tbl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Table (Truncate)'),
        content: Text(
          'This will permanently delete ALL rows in "${tbl.displayName}" (${tbl.name}).\n\nThe table structure and fields are preserved, but every record will be erased. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty Table'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final client = ref.read(apiClientProvider);
      await client.truncateTable(tbl.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Table "${tbl.displayName}" has been emptied.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error emptying table: $e')),
        );
      }
    }
  }

  Future<void> _showDeleteTableDialog(TableModel tbl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Table "${tbl.displayName}"?'),
        content: Text(
          'This will permanently drop the table "${tbl.name}" and ALL of its data, including every record and field definition. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Table'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final client = ref.read(apiClientProvider);
      await client.deleteTable(tbl.id);
      if (_selectedTable?.id == tbl.id) {
        setState(() => _selectedTable = null);
      }
      await _loadTables();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting table: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 850, maxWidth: 1200, minHeight: 600, maxHeight: 820),
        child: Column(
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.storage, size: 20),
                  const SizedBox(width: 8),
                  const Text('Manage Database', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.table_chart), text: 'Tables'),
                Tab(icon: Icon(Icons.view_column), text: 'Fields'),
                Tab(icon: Icon(Icons.hub), text: 'Relationships Graph'),
              ],
            ),
            if (_errorMessage != null)
              Container(
                color: Colors.red.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 18, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Error loading schema: $_errorMessage',
                          style: const TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                    TextButton(onPressed: _loadTables, child: const Text('Retry')),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTablesTab(),
                        _buildFieldsTab(),
                        _buildRelationshipsGraphTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTableContextMenu(Offset position, TableModel tbl) async {
    setState(() => _selectedTable = tbl);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(
          value: 'fields',
          child: Row(
            children: [
              Icon(Icons.view_column, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('Manage Fields'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Rename Table...'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 18),
              SizedBox(width: 8),
              Text('Duplicate Table'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'truncate',
          child: Row(
            children: [
              Icon(Icons.cleaning_services_outlined, size: 18, color: Colors.orange),
              SizedBox(width: 8),
              Text('Empty Table (Truncate)...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Table...', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (selected == 'fields') {
      _tabController.animateTo(1);
    } else if (selected == 'rename') {
      _showRenameTableDialog(tbl);
    } else if (selected == 'duplicate') {
      _showDuplicateTableDialog(tbl);
    } else if (selected == 'truncate') {
      _showTruncateTableDialog(tbl);
    } else if (selected == 'delete') {
      _showDeleteTableDialog(tbl);
    }
  }

  Widget _buildTablesTab() {
    final filteredTables = _tableSearchFilter.trim().isEmpty
        ? _tables
        : _tables.where((t) =>
            t.displayName.toLowerCase().contains(_tableSearchFilter.toLowerCase()) ||
            t.name.toLowerCase().contains(_tableSearchFilter.toLowerCase())).toList();

    return Column(
      children: [
        // Top Toolbar: Search filter, Table count, Refresh, and Create Table
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Filter tables...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) => setState(() => _tableSearchFilter = val),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  onPressed: _loadTables,
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '${_tables.length} tables in database',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Table...'),
                  onPressed: _showNewTableDialog,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Tables List
        Expanded(
          child: filteredTables.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.table_chart_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        _tables.isEmpty ? 'No tables found in this database.' : 'No tables match "$_tableSearchFilter"',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (_tables.isEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Create First Table'),
                          onPressed: _showNewTableDialog,
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filteredTables.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final tbl = filteredTables[idx];
                    final isSelected = tbl.id == _selectedTable?.id;
                    final occCount = _occurrences.where((o) => o.baseTableId == tbl.id).length;

                    return GestureDetector(
                      onSecondaryTapUp: (details) => _showTableContextMenu(details.globalPosition, tbl),
                      child: Container(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25)
                            : null,
                        child: ListTile(
                          selected: isSelected,
                          leading: Icon(
                            Icons.table_chart,
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                          ),
                          title: Row(
                            children: [
                              Text(
                                tbl.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                                ),
                              ),
                              if (occCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                                  ),
                                  child: Text(
                                    '$occCount in graph',
                                    style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text('SQL Table: ${tbl.name} • ${tbl.columns.length} fields'),
                          onTap: () => setState(() => _selectedTable = tbl),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Manage Fields shortcut
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.view_column_outlined, size: 15),
                                label: const Text('Fields', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  setState(() => _selectedTable = tbl);
                                  _tabController.animateTo(1);
                                },
                              ),
                              const SizedBox(width: 6),
                              const SizedBox(height: 24, child: VerticalDivider(width: 1)),
                              const SizedBox(width: 4),
                              // Rename
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Rename Table',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showRenameTableDialog(tbl),
                              ),
                              // Duplicate
                              IconButton(
                                icon: const Icon(Icons.copy_outlined, size: 18),
                                tooltip: 'Duplicate Table',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showDuplicateTableDialog(tbl),
                              ),
                              // Truncate / Empty
                              IconButton(
                                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                                tooltip: 'Empty Table (Truncate)',
                                visualDensity: VisualDensity.compact,
                                color: Colors.orange.shade700,
                                onPressed: () => _showTruncateTableDialog(tbl),
                              ),
                              // Delete
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'Delete Table',
                                visualDensity: VisualDensity.compact,
                                color: Colors.red.shade700,
                                onPressed: () => _showDeleteTableDialog(tbl),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Canonical FileMaker Bottom Action Panel
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedTable != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_chart, size: 15, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Selected: ${_selectedTable!.displayName} (${_selectedTable!.columns.length} fields)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  Text(
                    'Select a table above to manage its schema or data.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Rename...'),
                  onPressed: _selectedTable != null ? () => _showRenameTableDialog(_selectedTable!) : null,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Duplicate'),
                  onPressed: _selectedTable != null ? () => _showDuplicateTableDialog(_selectedTable!) : null,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16, color: Colors.orange),
                  label: const Text('Empty...'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
                  onPressed: _selectedTable != null ? () => _showTruncateTableDialog(_selectedTable!) : null,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete...'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _selectedTable != null ? () => _showDeleteTableDialog(_selectedTable!) : null,
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.view_column_outlined, size: 16),
                  label: const Text('Manage Fields ->'),
                  onPressed: _selectedTable != null
                      ? () => _tabController.animateTo(1)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldsTab() {
    if (_selectedTable == null) {
      return const Center(child: Text('Select a table from the Tables tab to manage its fields.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Text(
                'Fields for: ${_selectedTable!.displayName} (${_selectedTable!.name})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New Field...'),
                onPressed: _showNewFieldDialog,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _selectedTable!.columns.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final col = _selectedTable!.columns[idx];
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(col.fieldType[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                title: Row(
                  children: [
                    Text(col.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (col.isPrimaryKey) ...[
                      const SizedBox(width: 8),
                      const Chip(
                        label: Text('Primary Key', style: TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                subtitle: Text('Identifier: ${col.name} • Agnostic Type: ${col.fieldType}'),
                onTap: () => _showFieldOptionsDialog(col),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.tune, size: 14),
                      label: const Text('Options...', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showFieldOptionsDialog(col),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      col.isNullable ? 'Nullable' : 'Required',
                      style: TextStyle(fontSize: 12, color: col.isNullable ? Colors.grey : Colors.blue),
                    ),
                    if (!col.isPrimaryKey) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: 'Rename Field',
                        onPressed: () => _showEditFieldDialog(col),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        tooltip: 'Delete Field',
                        onPressed: () => _showDeleteFieldDialog(col),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRelationshipsGraphTab() {
    return RelationshipGraphWidget(
      tables: _tables,
      occurrences: _occurrences,
      relationships: _relationships,
      apiClient: ref.read(apiClientProvider),
      onSchemaChanged: _loadTables,
    );
  }
}
