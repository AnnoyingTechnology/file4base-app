import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/file4base_status_sidebar.dart' show LayoutTool;
import '../schema_manager/manage_database_dialog.dart';
import '../theme_manager/manage_themes_dialog.dart';
import 'manage_layouts_dialog.dart';
import 'models/layout_definition.dart';

enum _ResizeHandle {
  topLeft,
  topCenter,
  topRight,
  middleRight,
  bottomRight,
  bottomCenter,
  bottomLeft,
  middleLeft,
}

enum _LayoutSaveStatus { idle, dirty, saving, saved, error }

class LayoutDesignerWidget extends StatefulWidget {
  final TableModel table;
  final List<TableModel> tables;
  final ApiClient apiClient;
  final LayoutDefinitionModel initialLayout;
  final List<LayoutModel> layouts;
  final ValueChanged<LayoutModel>? onLayoutSelected;
  final VoidCallback? onNewLayout;
  final VoidCallback? onManageLayouts;
  final VoidCallback? onRenameLayout;
  final VoidCallback? onExitLayout;
  final VoidCallback? onManageDatabase;
  final VoidCallback? onManageSecurity;
  final VoidCallback? onManageScripts;
  final VoidCallback? onManageThemes;
  final VoidCallback onSaved;
  final VoidCallback? onAutoSaveDirty;
  final ValueChanged<LayoutDefinitionModel>? onLayoutChanged;
  final LayoutTool activeTool;

  const LayoutDesignerWidget({
    super.key,
    required this.table,
    this.tables = const [],
    required this.apiClient,
    required this.initialLayout,
    this.layouts = const [],
    this.onLayoutSelected,
    this.onNewLayout,
    this.onManageLayouts,
    this.onRenameLayout,
    this.onExitLayout,
    this.onManageDatabase,
    this.onManageSecurity,
    this.onManageScripts,
    this.onManageThemes,
    required this.onSaved,
    this.onAutoSaveDirty,
    this.onLayoutChanged,
    this.activeTool = LayoutTool.pointer,
  });

  @override
  State<LayoutDesignerWidget> createState() => LayoutDesignerWidgetState();
}

class LayoutDesignerWidgetState extends State<LayoutDesignerWidget> {
  late LayoutDefinitionModel _layout;
  late LayoutTool _activeTool;
  late TableModel _currentTable;
  String? _selectedObjectId;
  bool _snapToGrid = true;
  bool _showGrid = true;
  bool _isSaving = false;
  bool _isPersisted = false;

  // Panes toggle
  bool _showLeftPane = true;
  bool _showRightPane = true;
  int _leftPaneTab = 0; // 0 = Fields, 1 = Objects
  int _inspectorTab = 0; // 0 = Position, 1 = Styles, 2 = Data, 3 = Text

  // Left Pane filters & preferences
  String _fieldSearchQuery = '';
  String _objectSearchQuery = '';
  bool _sortFieldsAsc = false;
  String _dragPlacement = 'horizontal'; // 'horizontal' or 'vertical'
  bool _dragIncludeLabel = true;
  String _dragControlStyle = 'edit_box';
  bool _dragPreferencesExpanded = false;

  // Part resizing state
  String? _resizingPartType; // 'header', 'body', 'footer'
  double _partResizeStartY = 0;
  double _partResizeStartHeight = 0;
  double _partResizeCurrentHeight = 0;

  // Object 8-handle resizing state
  _ResizeHandle? _activeResizeHandle;
  Offset _objResizeStart = Offset.zero;
  Rect? _objResizeStartBounds;

  // Dragging objects on canvas
  final Map<String, Offset> _dragStart = {};
  final Map<String, Offset> _objStartPos = {};

  // Undo / Redo stacks
  final List<LayoutDefinitionModel> _undoStack = [];
  final List<LayoutDefinitionModel> _redoStack = [];

  // Auto-save debounce
  Timer? _autoSaveTimer;
  _LayoutSaveStatus _autoSaveStatus = _LayoutSaveStatus.idle;
  static const _autoSaveDelay = Duration(milliseconds: 1500);

  // Global key for canvas drag target
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _layout = _ensureStandardParts(widget.initialLayout);
    _activeTool = widget.activeTool;
    _currentTable = widget.table;
    _isPersisted = !_layout.id.startsWith('layout_');
  }

  @override
  void didUpdateWidget(covariant LayoutDesignerWidget old) {
    super.didUpdateWidget(old);
    if (old.initialLayout.id != widget.initialLayout.id ||
        old.initialLayout.name != widget.initialLayout.name) {
      _layout = _ensureStandardParts(widget.initialLayout);
      _selectedObjectId = null;
      _isPersisted = !_layout.id.startsWith('layout_');
      _undoStack.clear();
      _redoStack.clear();
    }
    if (old.activeTool != widget.activeTool) {
      _activeTool = widget.activeTool;
    }
    if (old.table.id != widget.table.id) {
      _currentTable = widget.table;
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (_autoSaveStatus == _LayoutSaveStatus.dirty) {
      widget.onLayoutChanged?.call(_layout);
      if (_isPersisted) {
        widget.apiClient.updateLayout(_layout.id, _layout.name, _layout.toJson()).catchError((_) => null as LayoutModel);
      }
    }
    super.dispose();
  }

  LayoutDefinitionModel _ensureStandardParts(LayoutDefinitionModel def) {
    var parts = List<LayoutPartModel>.from(def.parts);
    if (parts.isEmpty) {
      parts = [
        const LayoutPartModel(id: 'header_part', type: 'header', height: 60.0),
        const LayoutPartModel(id: 'body_part', type: 'body', height: 400.0),
        const LayoutPartModel(id: 'footer_part', type: 'footer', height: 40.0),
      ];
      return def.copyWith(parts: parts);
    }
    bool hasHeader = parts.any((p) => p.type == 'header');
    bool hasBody = parts.any((p) => p.type == 'body');
    bool hasFooter = parts.any((p) => p.type == 'footer');

    if (!hasHeader) {
      parts.insert(0, const LayoutPartModel(id: 'header_part', type: 'header', height: 60.0));
    }
    if (!hasBody) {
      parts.insert(1, const LayoutPartModel(id: 'body_part', type: 'body', height: 400.0));
    }
    if (!hasFooter) {
      parts.add(const LayoutPartModel(id: 'footer_part', type: 'footer', height: 40.0));
    }
    return def.copyWith(parts: parts);
  }

  LayoutPartModel get _headerPart =>
      _layout.parts.firstWhere((p) => p.type == 'header', orElse: () => const LayoutPartModel(id: 'h', type: 'header', height: 60));
  LayoutPartModel get _bodyPart =>
      _layout.parts.firstWhere((p) => p.type == 'body', orElse: () => const LayoutPartModel(id: 'b', type: 'body', height: 400));
  LayoutPartModel get _footerPart =>
      _layout.parts.firstWhere((p) => p.type == 'footer', orElse: () => const LayoutPartModel(id: 'f', type: 'footer', height: 40));

  LayoutObjectModel? get _selectedObject {
    if (_selectedObjectId == null) return null;
    try {
      return _layout.objects.firstWhere((o) => o.id == _selectedObjectId);
    } catch (_) {
      return null;
    }
  }

  double _snap(double value) {
    if (!_snapToGrid) return value;
    return (value / 8.0).roundToDouble() * 8.0;
  }

  void _pushUndoState() {
    _undoStack.add(_layout);
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_layout);
    final previous = _undoStack.removeLast();
    setState(() {
      _layout = previous;
      if (_selectedObjectId != null && !_layout.objects.any((o) => o.id == _selectedObjectId)) {
        _selectedObjectId = null;
      }
    });
    _markLayoutDirty();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_layout);
    final next = _redoStack.removeLast();
    setState(() {
      _layout = next;
    });
    _markLayoutDirty();
  }

  void _markLayoutDirty() {
    _autoSaveTimer?.cancel();
    widget.onLayoutChanged?.call(_layout);
    setState(() => _autoSaveStatus = _LayoutSaveStatus.dirty);
    _autoSaveTimer = Timer(_autoSaveDelay, _performAutoSave);
  }

  Future<LayoutDefinitionModel> commitAndSave() async {
    _autoSaveTimer?.cancel();
    try {
      if (_isPersisted) {
        await widget.apiClient.updateLayout(
          _layout.id,
          _layout.name,
          _layout.toJson(),
        );
      } else {
        final created = await widget.apiClient.createLayout(
          _layout.name,
          toId: _currentTable.id,
          definition: _layout.toJson(),
        );
        _layout = _layout.copyWith(id: created.id);
        _isPersisted = true;
      }
      widget.onLayoutChanged?.call(_layout);
      widget.onSaved();
      widget.onAutoSaveDirty?.call();
      if (mounted) setState(() => _autoSaveStatus = _LayoutSaveStatus.saved);
    } catch (_) {
      widget.onLayoutChanged?.call(_layout);
    }
    return _layout;
  }

  Future<void> _performAutoSave() async {
    if (_isSaving) return;
    setState(() => _autoSaveStatus = _LayoutSaveStatus.saving);
    try {
      if (_isPersisted) {
        await widget.apiClient.updateLayout(
          _layout.id,
          _layout.name,
          _layout.toJson(),
        );
      } else {
        final created = await widget.apiClient.createLayout(
          _layout.name,
          toId: _currentTable.id,
          definition: _layout.toJson(),
        );
        _layout = _layout.copyWith(id: created.id);
        _isPersisted = true;
      }
      if (mounted) {
        setState(() => _autoSaveStatus = _LayoutSaveStatus.saved);
        widget.onLayoutChanged?.call(_layout);
        widget.onAutoSaveDirty?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _autoSaveStatus = _LayoutSaveStatus.error);
    }
  }

  Future<void> saveLayoutExplicitly() async {
    setState(() => _isSaving = true);
    try {
      await commitAndSave();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Layout "${_layout.name}" saved successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save layout: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> saveLayout() => saveLayoutExplicitly();

  // ─── Part Resizing Logic ───────────────────────────────────────────────────

  void _onPartResizeStart(String partType, DragStartDetails details) {
    _pushUndoState();
    final currentH = switch (partType) {
      'header' => _headerPart.height,
      'body' => _bodyPart.height,
      'footer' => _footerPart.height,
      _ => 60.0,
    };
    setState(() {
      _resizingPartType = partType;
      _partResizeStartY = details.globalPosition.dy;
      _partResizeStartHeight = currentH;
      _partResizeCurrentHeight = currentH;
    });
  }

  void _onPartResizeUpdate(DragUpdateDetails details) {
    if (_resizingPartType == null) return;
    final delta = details.globalPosition.dy - _partResizeStartY;
    double newHeight = _partResizeStartHeight + delta;

    switch (_resizingPartType) {
      case 'header':
        newHeight = newHeight.clamp(20.0, 800.0);
        break;
      case 'body':
        newHeight = newHeight.clamp(40.0, 3000.0);
        break;
      case 'footer':
        newHeight = newHeight.clamp(20.0, 600.0);
        break;
    }

    if (_snapToGrid) {
      newHeight = (newHeight / 8.0).roundToDouble() * 8.0;
    }

    setState(() {
      _partResizeCurrentHeight = newHeight;
      final updatedParts = _layout.parts.map((p) {
        if (p.type == _resizingPartType) {
          return p.copyWith(height: newHeight);
        }
        return p;
      }).toList();
      _layout = _layout.copyWith(parts: updatedParts);
    });
  }

  void _onPartResizeEnd(DragEndDetails details) {
    if (_resizingPartType == null) return;
    setState(() {
      _resizingPartType = null;
    });
    _markLayoutDirty();
  }

  Future<void> _showPartSetupDialog(String partType) async {
    final currentPart = _layout.parts.firstWhere((p) => p.type == partType,
        orElse: () => LayoutPartModel(id: partType, type: partType, height: 60));
    final heightCtrl = TextEditingController(text: currentPart.height.round().toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.table_rows, color: Color(0xFF1E88E5)),
            const SizedBox(width: 8),
            Text('${partType.toUpperCase()} Part Setup'),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Adjust the height for the $partType part in points (pt):',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: heightCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Part Height (pt)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Apply')),
        ],
      ),
    );

    if (confirmed == true) {
      final h = double.tryParse(heightCtrl.text);
      if (h != null && h > 10) {
        _pushUndoState();
        setState(() {
          final updatedParts = _layout.parts.map((p) {
            if (p.type == partType) return p.copyWith(height: h);
            return p;
          }).toList();
          _layout = _layout.copyWith(parts: updatedParts);
        });
        _markLayoutDirty();
      }
    }
  }

  // ─── Object Creation & Placement ───────────────────────────────────────────

  void _placeObjectFromTool(Offset localPos) {
    if (_activeTool == LayoutTool.pointer ||
        _activeTool == LayoutTool.format ||
        _activeTool == LayoutTool.rotate) {
      return;
    }

    if (_activeTool == LayoutTool.part) {
      _showPartSetupDialog('body');
      setState(() => _activeTool = LayoutTool.pointer);
      return;
    }

    _pushUndoState();
    final newId = 'obj_${DateTime.now().millisecondsSinceEpoch}';
    final x = _snap(localPos.dx - 60).clamp(0.0, _layout.width - 40);
    final y = _snap(localPos.dy - 18).clamp(0.0, 3000.0);

    LayoutObjectModel newObj;
    switch (_activeTool) {
      case LayoutTool.text:
        newObj = LayoutObjectModel(
          id: newId, type: 'label', x: x, y: y, width: 140, height: 26,
          text: 'Text Label',
          style: const LayoutObjectStyle(fontSize: 13, fontWeight: 'normal'),
        );
        break;
      case LayoutTool.line:
        newObj = LayoutObjectModel(
          id: newId, type: 'line', x: x, y: y, width: 160, height: 2,
          style: const LayoutObjectStyle(borderColor: '#9E9E9E', borderWidth: 1),
        );
        break;
      case LayoutTool.rectangle:
        newObj = LayoutObjectModel(
          id: newId, type: 'rect', x: x, y: y, width: 140, height: 70,
          style: const LayoutObjectStyle(borderColor: '#9E9E9E', borderWidth: 1),
        );
        break;
      case LayoutTool.roundedRect:
        newObj = LayoutObjectModel(
          id: newId, type: 'rounded_rect', x: x, y: y, width: 140, height: 70,
          style: const LayoutObjectStyle(borderColor: '#9E9E9E', borderWidth: 1, cornerRadius: 8),
        );
        break;
      case LayoutTool.oval:
        newObj = LayoutObjectModel(
          id: newId, type: 'oval', x: x, y: y, width: 90, height: 90,
          style: const LayoutObjectStyle(borderColor: '#9E9E9E', borderWidth: 1),
        );
        break;
      case LayoutTool.field:
        final cols = _currentTable.columns.where((c) => !c.isPrimaryKey).toList();
        final defaultCol = cols.isNotEmpty ? cols.first.name : 'field';
        newObj = LayoutObjectModel(
          id: newId, type: 'field', x: x, y: y, width: 220, height: 32,
          fieldBinding: FieldBindingModel(fieldName: defaultCol),
        );
        break;
      case LayoutTool.button:
        newObj = LayoutObjectModel(
          id: newId, type: 'button', x: x, y: y, width: 130, height: 34,
          text: 'Button',
          style: const LayoutObjectStyle(fillColor: '#1E88E5', textColor: '#FFFFFF', cornerRadius: 5),
        );
        break;
      case LayoutTool.popoverButton:
        newObj = LayoutObjectModel(
          id: newId, type: 'popover_button', x: x, y: y, width: 140, height: 34,
          text: 'Popover',
          style: const LayoutObjectStyle(fillColor: '#ECEFF1', textColor: '#263238', cornerRadius: 5),
        );
        break;
      case LayoutTool.buttonBar:
        newObj = LayoutObjectModel(
          id: newId, type: 'button_bar', x: x, y: y, width: 270, height: 34,
          text: 'Segment 1 | Segment 2 | Segment 3',
          style: const LayoutObjectStyle(fillColor: '#FFFFFF', borderColor: '#B0BEC5', cornerRadius: 4),
        );
        break;
      case LayoutTool.tabControl:
        newObj = LayoutObjectModel(
          id: newId, type: 'tab_control', x: x, y: y, width: 340, height: 180,
          text: 'Tab 1 | Tab 2',
          style: const LayoutObjectStyle(fillColor: '#FAFAFA', borderColor: '#CFD8DC', cornerRadius: 4),
        );
        break;
      case LayoutTool.portal:
        newObj = LayoutObjectModel(
          id: newId, type: 'portal', x: x, y: y, width: 440, height: 180,
          text: 'Related Records Portal',
          style: const LayoutObjectStyle(fillColor: '#FFFFFF', borderColor: '#90CAF9', cornerRadius: 4),
        );
        break;
      case LayoutTool.chart:
        newObj = LayoutObjectModel(
          id: newId, type: 'chart', x: x, y: y, width: 320, height: 200,
          text: 'Chart Preview',
          style: const LayoutObjectStyle(fillColor: '#FFFFFF', borderColor: '#B0BEC5', cornerRadius: 6),
        );
        break;
      case LayoutTool.webViewer:
        newObj = LayoutObjectModel(
          id: newId, type: 'web_viewer', x: x, y: y, width: 380, height: 220,
          text: 'https://example.com',
          style: const LayoutObjectStyle(fillColor: '#FFFFFF', borderColor: '#90A4AE', cornerRadius: 4),
        );
        break;
      default:
        newObj = LayoutObjectModel(
          id: newId, type: 'label', x: x, y: y, width: 140, height: 26, text: 'Label',
        );
    }

    setState(() {
      _layout = _layout.copyWith(objects: [..._layout.objects, newObj]);
      _selectedObjectId = newId;
      _activeTool = LayoutTool.pointer; // Return to pointer after placing
    });
    _markLayoutDirty();
  }

  void _placeFieldAt({required ColumnModel column, required Offset pos}) {
    _pushUndoState();
    final x = _snap(pos.dx).clamp(0.0, _layout.width - 240);
    final y = _snap(pos.dy).clamp(0.0, 3000.0);
    final List<LayoutObjectModel> newObjects = [];

    if (_dragIncludeLabel) {
      if (_dragPlacement == 'horizontal') {
        // Label to left, field to right
        final lblId = 'lbl_${DateTime.now().millisecondsSinceEpoch}';
        final fldId = 'fld_${DateTime.now().millisecondsSinceEpoch + 1}';
        newObjects.add(
          LayoutObjectModel(
            id: lblId,
            type: 'label',
            x: x,
            y: y + 4,
            width: 120,
            height: 24,
            text: column.displayName,
            style: const LayoutObjectStyle(fontSize: 12, fontWeight: 'bold', textAlign: 'right'),
          ),
        );
        newObjects.add(
          LayoutObjectModel(
            id: fldId,
            type: 'field',
            x: x + 128,
            y: y,
            width: 220,
            height: 32,
            fieldBinding: FieldBindingModel(
              fieldName: column.name,
              controlStyle: _dragControlStyle,
            ),
          ),
        );
      } else {
        // Label on top, field below
        final lblId = 'lbl_${DateTime.now().millisecondsSinceEpoch}';
        final fldId = 'fld_${DateTime.now().millisecondsSinceEpoch + 1}';
        newObjects.add(
          LayoutObjectModel(
            id: lblId,
            type: 'label',
            x: x,
            y: y,
            width: 220,
            height: 20,
            text: column.displayName,
            style: const LayoutObjectStyle(fontSize: 12, fontWeight: 'bold', textAlign: 'left'),
          ),
        );
        newObjects.add(
          LayoutObjectModel(
            id: fldId,
            type: 'field',
            x: x,
            y: y + 22,
            width: 220,
            height: 32,
            fieldBinding: FieldBindingModel(
              fieldName: column.name,
              controlStyle: _dragControlStyle,
            ),
          ),
        );
      }
    } else {
      // Just the field
      final fldId = 'fld_${DateTime.now().millisecondsSinceEpoch}';
      newObjects.add(
        LayoutObjectModel(
          id: fldId,
          type: 'field',
          x: x,
          y: y,
          width: 240,
          height: 32,
          fieldBinding: FieldBindingModel(
            fieldName: column.name,
            controlStyle: _dragControlStyle,
          ),
        ),
      );
    }

    setState(() {
      _layout = _layout.copyWith(objects: [..._layout.objects, ...newObjects]);
      _selectedObjectId = newObjects.last.id;
    });
    _markLayoutDirty();
  }

  void _deleteSelectedObject() {
    if (_selectedObjectId == null) return;
    _pushUndoState();
    setState(() {
      _layout = _layout.copyWith(
        objects: _layout.objects.where((o) => o.id != _selectedObjectId).toList(),
      );
      _selectedObjectId = null;
    });
    _markLayoutDirty();
  }

  void _duplicateSelectedObject() {
    final sel = _selectedObject;
    if (sel == null) return;
    _pushUndoState();
    final dupId = 'obj_${DateTime.now().millisecondsSinceEpoch}';
    final dup = sel.copyWith(
      id: dupId,
      x: _snap(sel.x + 16),
      y: _snap(sel.y + 16),
    );
    setState(() {
      _layout = _layout.copyWith(objects: [..._layout.objects, dup]);
      _selectedObjectId = dupId;
    });
    _markLayoutDirty();
  }

  void _bringToFront() {
    final sel = _selectedObject;
    if (sel == null) return;
    _pushUndoState();
    setState(() {
      final list = _layout.objects.where((o) => o.id != sel.id).toList()..add(sel);
      _layout = _layout.copyWith(objects: list);
    });
    _markLayoutDirty();
  }

  void _sendToBack() {
    final sel = _selectedObject;
    if (sel == null) return;
    _pushUndoState();
    setState(() {
      final list = [sel, ..._layout.objects.where((o) => o.id != sel.id)];
      _layout = _layout.copyWith(objects: list);
    });
    _markLayoutDirty();
  }

  void _alignSelected(String alignment) {
    final sel = _selectedObject;
    if (sel == null) return;
    _pushUndoState();
    double newX = sel.x;
    double newY = sel.y;

    switch (alignment) {
      case 'left':
        newX = 24.0;
        break;
      case 'center':
        newX = _snap((_layout.width - sel.width) / 2);
        break;
      case 'right':
        newX = _snap(_layout.width - sel.width - 24);
        break;
      case 'top':
        newY = 16.0;
        break;
      case 'middle':
        newY = _snap(_headerPart.height + (_bodyPart.height - sel.height) / 2);
        break;
      case 'bottom':
        newY = _snap(_headerPart.height + _bodyPart.height - sel.height - 16);
        break;
    }

    setState(() {
      _layout = _layout.copyWith(
        objects: _layout.objects.map((o) => o.id == sel.id ? o.copyWith(x: newX, y: newY) : o).toList(),
      );
    });
    _markLayoutDirty();
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  Future<void> _showNewFieldDialog() async {
    final nameCtrl = TextEditingController();
    String selectedType = 'varchar';
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_box_outlined, color: Color(0xFF1E88E5)),
              SizedBox(width: 8),
              Text('Create New Field'),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add a new field to "${_currentTable.displayName}":',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Field Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Please enter a field name' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Field Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'varchar', child: Text('Text (varchar)')),
                      DropdownMenuItem(value: 'int', child: Text('Number / Integer (int)')),
                      DropdownMenuItem(value: 'numeric', child: Text('Decimal / Number (numeric)')),
                      DropdownMenuItem(value: 'date', child: Text('Date (date)')),
                      DropdownMenuItem(value: 'time', child: Text('Time (time)')),
                      DropdownMenuItem(value: 'timestamp', child: Text('Timestamp (timestamp)')),
                      DropdownMenuItem(value: 'boolean', child: Text('Boolean (boolean)')),
                      DropdownMenuItem(value: 'json', child: Text('Container / JSON (json)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => selectedType = v);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Create Field'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final fName = nameCtrl.text.trim();
      try {
        await widget.apiClient.addColumn(
          _currentTable.id,
          name: fName,
          displayName: fName,
          fieldType: selectedType,
        );
        final refreshedTables = await widget.apiClient.listTables();
        final match = refreshedTables.firstWhere((t) => t.id == _currentTable.id, orElse: () => _currentTable);
        setState(() {
          _currentTable = match;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Field "$fName" added to ${_currentTable.displayName}!'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create field: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showRenameDialog() async {
    final ctrl = TextEditingController(text: _layout.name);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Color(0xFF1E88E5)),
            SizedBox(width: 8),
            Text('Rename Layout'),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter new layout name:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Rename')),
        ],
      ),
    );

    if (confirmed != null && confirmed.trim().isNotEmpty && confirmed.trim() != _layout.name) {
      _pushUndoState();
      setState(() {
        _layout = _layout.copyWith(name: confirmed.trim());
      });
      await commitAndSave();
    }
  }

  // ─── Build UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_selectedObjectId != null) {
              _deleteSelectedObject();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.keyD &&
              (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
            _duplicateSelectedObject();
          } else if (event.logicalKey == LogicalKeyboardKey.keyZ &&
              (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
            if (HardwareKeyboard.instance.isShiftPressed) {
              _redo();
            } else {
              _undo();
            }
          }
        }
      },
      child: Container(
        color: isDark ? const Color(0xFF1A1E24) : const Color(0xFFE5E5E7),
        child: Column(
          children: [
            // Bar 1: Top FileMaker Layout Tools Toolbar
            _buildLayoutToolsToolbar(context, isDark),
            // Bar 2: Layout Context & Options Subbar
            _buildLayoutContextBar(context, isDark),
            const Divider(height: 1, thickness: 1),
            // Center Workspace: Left Pane + Canvas + Right Inspector
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showLeftPane) ...[
                    SizedBox(width: 250, child: _buildLeftPane(context, isDark)),
                    const VerticalDivider(width: 1, thickness: 1),
                  ],
                  // Canvas Area
                  Expanded(child: _buildCanvasArea(context, isDark)),
                  if (_showRightPane) ...[
                    const VerticalDivider(width: 1, thickness: 1),
                    SizedBox(width: 280, child: _buildRightInspector(context, isDark)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bar 1: Layout Tools Toolbar ───────────────────────────────────────────

  Widget _buildLayoutToolsToolbar(BuildContext context, bool isDark) {
    final barBg = isDark ? const Color(0xFF22272E) : const Color(0xFFF3F3F5);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(
        children: [
          // Left: New Layout / Report
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
            icon: const Icon(Icons.add, size: 15, color: Colors.green),
            label: const Text('New Layout / Report',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            onPressed: widget.onNewLayout,
          ),
          const SizedBox(width: 14),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          const SizedBox(width: 10),

          // Center: Layout Tools Label & Palette
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Layout Tools',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: isDark ? Colors.white60 : Colors.black54)),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toolItem(LayoutTool.pointer, Icons.near_me, 'Pointer (Select/Move)'),
                      _toolItem(LayoutTool.text, Icons.title, 'Text Tool'),
                      _toolItem(LayoutTool.line, Icons.horizontal_rule, 'Line Tool'),
                      _toolItem(LayoutTool.rectangle, Icons.crop_square, 'Rectangle Tool'),
                      _toolItem(LayoutTool.roundedRect, Icons.crop_square_rounded, 'Rounded Rectangle Tool'),
                      _toolItem(LayoutTool.oval, Icons.circle_outlined, 'Oval Tool'),
                      const SizedBox(width: 4),
                      Container(height: 18, width: 1, color: isDark ? Colors.white24 : Colors.black12),
                      const SizedBox(width: 4),
                      _toolItem(LayoutTool.field, Icons.input, 'Field / Control Tool'),
                      _toolItem(LayoutTool.button, Icons.smart_button, 'Button Tool'),
                      _toolItem(LayoutTool.popoverButton, Icons.open_in_new, 'Popover Button Tool'),
                      _toolItem(LayoutTool.buttonBar, Icons.view_column_outlined, 'Button Bar Tool'),
                      _toolItem(LayoutTool.tabControl, Icons.tab_outlined, 'Tab Control Tool'),
                      _toolItem(LayoutTool.portal, Icons.table_chart_outlined, 'Portal Tool'),
                      _toolItem(LayoutTool.chart, Icons.bar_chart, 'Chart Tool'),
                      _toolItem(LayoutTool.webViewer, Icons.language, 'Web Viewer Tool'),
                      const SizedBox(width: 4),
                      Container(height: 18, width: 1, color: isDark ? Colors.white24 : Colors.black12),
                      const SizedBox(width: 4),
                      _toolItem(LayoutTool.part, Icons.table_rows_outlined, 'Part Tool (Setup Parts)'),
                      _toolItem(LayoutTool.format, Icons.brush_outlined, 'Format Painter'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          const SizedBox(width: 10),

          // Right: Manage Menu & Show/Hide Panes
          PopupMenuButton<String>(
            tooltip: 'Manage System Artifacts',
            onSelected: (val) {
              switch (val) {
                case 'db':
                  widget.onManageDatabase?.call();
                  break;
                case 'layouts':
                  widget.onManageLayouts?.call();
                  break;
                case 'security':
                  widget.onManageSecurity?.call();
                  break;
                case 'scripts':
                  widget.onManageScripts?.call();
                  break;
                case 'themes':
                  widget.onManageThemes?.call();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'db',
                child: Row(
                  children: [
                    Icon(Icons.storage, size: 16, color: Color(0xFF1E88E5)),
                    SizedBox(width: 8),
                    Text('Database...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'layouts',
                child: Row(
                  children: [
                    Icon(Icons.view_quilt, size: 16, color: Color(0xFF1E88E5)),
                    SizedBox(width: 8),
                    Text('Layouts...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.security, size: 16, color: Color(0xFF1E88E5)),
                    SizedBox(width: 8),
                    Text('Security...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'scripts',
                child: Row(
                  children: [
                    Icon(Icons.code, size: 16, color: Color(0xFF1E88E5)),
                    SizedBox(width: 8),
                    Text('Script Workspace...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'themes',
                child: Row(
                  children: [
                    Icon(Icons.palette, size: 16, color: Color(0xFF1E88E5)),
                    SizedBox(width: 8),
                    Text('Themes...'),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
              ),
              child: const Row(
                children: [
                  Icon(Icons.settings, size: 15),
                  SizedBox(width: 4),
                  Text('Manage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  Icon(Icons.arrow_drop_down, size: 15),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Show/Hide Left & Right Panes
          Tooltip(
            message: _showLeftPane ? 'Hide Fields & Objects Pane' : 'Show Fields & Objects Pane',
            child: IconButton(
              icon: Icon(
                _showLeftPane ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                size: 18,
                color: _showLeftPane ? const Color(0xFF1E88E5) : (isDark ? Colors.white60 : Colors.black54),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _showLeftPane = !_showLeftPane),
            ),
          ),
          Tooltip(
            message: _showRightPane ? 'Hide Inspector Pane' : 'Show Inspector Pane',
            child: IconButton(
              icon: Icon(
                _showRightPane ? Icons.tune : Icons.tune_outlined,
                size: 18,
                color: _showRightPane ? const Color(0xFF1E88E5) : (isDark ? Colors.white60 : Colors.black54),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _showRightPane = !_showRightPane),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolItem(LayoutTool tool, IconData icon, String tooltip) {
    final isActive = _activeTool == tool;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            _activeTool = tool;
          });
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: isActive
                ? (isDark ? const Color(0xFF1E88E5).withOpacity(0.35) : const Color(0xFF1E88E5).withOpacity(0.18))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? const Color(0xFF1E88E5) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive
                ? const Color(0xFF1E88E5)
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  // ─── Bar 2: Layout Context & Options Subbar ─────────────────────────────────

  Widget _buildLayoutContextBar(BuildContext context, bool isDark) {
    final subbarBg = isDark ? const Color(0xFF1E232B) : const Color(0xFFEBE9E4);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: subbarBg,
      child: Row(
        children: [
          // Layout Selector Dropdown
          Text('Layout:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
          const SizedBox(width: 6),
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D333B) : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.layouts.any((l) => l.id == _layout.id) ? _layout.id : null,
                hint: Text(_layout.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                icon: const Icon(Icons.arrow_drop_down, size: 16),
                isDense: true,
                items: widget.layouts.map((l) {
                  return DropdownMenuItem<String>(
                    value: l.id,
                    child: Text(l.name, style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final match = widget.layouts.firstWhere((l) => l.id == id);
                    widget.onLayoutSelected?.call(match);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Rename button
          Tooltip(
            message: 'Rename Layout',
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF1E88E5)),
              visualDensity: VisualDensity.compact,
              onPressed: _showRenameDialog,
            ),
          ),
          const SizedBox(width: 10),

          // Table Occurrence Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282E38) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.table_chart_outlined, size: 12, color: Colors.blue),
                const SizedBox(width: 4),
                Text('Table: ${_currentTable.displayName}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),

          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 6, endIndent: 6),
          const SizedBox(width: 8),

          // Theme Selector
          Text('Theme:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _layout.theme,
              isDense: true,
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87),
              items: const [
                DropdownMenuItem(value: 'Enlightened', child: Text('Enlightened')),
                DropdownMenuItem(value: 'Enlightened Touch', child: Text('Enlightened Touch')),
                DropdownMenuItem(value: 'Enlightened Print', child: Text('Enlightened Print')),
                DropdownMenuItem(value: 'Minimalist', child: Text('Minimalist')),
              ],
              onChanged: (newTheme) {
                if (newTheme != null) {
                  _pushUndoState();
                  setState(() => _layout = _layout.copyWith(theme: newTheme));
                  _markLayoutDirty();
                }
              },
            ),
          ),

          const SizedBox(width: 10),
          // Snap & Grid Toggles
          Tooltip(
            message: 'Snap to 8pt Grid',
            child: InkWell(
              onTap: () => setState(() => _snapToGrid = !_snapToGrid),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _snapToGrid ? const Color(0xFF1E88E5).withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _snapToGrid ? const Color(0xFF1E88E5) : Colors.transparent),
                ),
                child: Row(
                  children: [
                    Icon(Icons.grid_on, size: 13, color: _snapToGrid ? const Color(0xFF1E88E5) : Colors.grey),
                    const SizedBox(width: 4),
                    Text('Snap 8px', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _snapToGrid ? const Color(0xFF1E88E5) : Colors.grey)),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),

          // Undo / Redo
          IconButton(
            icon: const Icon(Icons.undo, size: 15),
            tooltip: 'Undo (Cmd+Z)',
            visualDensity: VisualDensity.compact,
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 15),
            tooltip: 'Redo (Cmd+Shift+Z)',
            visualDensity: VisualDensity.compact,
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),

          const SizedBox(width: 6),
          // Auto-save Indicator
          _buildAutoSaveIndicator(),

          const SizedBox(width: 12),
          // Prominent [ Exit Layout ] Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              elevation: 1,
            ),
            icon: const Icon(Icons.check_circle_outline, size: 14, color: Colors.white),
            label: const Text('Exit Layout',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () async {
              await commitAndSave();
              widget.onExitLayout?.call();
            },
          ),
        ],
      ),
    );
  }

  // ─── Left Pane: Fields & Objects ───────────────────────────────────────────

  Widget _buildLeftPane(BuildContext context, bool isDark) {
    final bg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF9F9FA);

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Pane Tabs (Fields | Objects)
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262C36) : const Color(0xFFECEEF1),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _leftPaneTab = 0),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _leftPaneTab == 0 ? bg : Colors.transparent,
                        border: _leftPaneTab == 0
                            ? const Border(top: BorderSide(color: Color(0xFF1E88E5), width: 2))
                            : null,
                      ),
                      child: Text('Fields',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _leftPaneTab == 0 ? FontWeight.bold : FontWeight.normal,
                            color: _leftPaneTab == 0 ? const Color(0xFF1E88E5) : (isDark ? Colors.white70 : Colors.black87),
                          )),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _leftPaneTab = 1),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _leftPaneTab == 1 ? bg : Colors.transparent,
                        border: _leftPaneTab == 1
                            ? const Border(top: BorderSide(color: Color(0xFF1E88E5), width: 2))
                            : null,
                      ),
                      child: Text('Objects',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _leftPaneTab == 1 ? FontWeight.bold : FontWeight.normal,
                            color: _leftPaneTab == 1 ? const Color(0xFF1E88E5) : (isDark ? Colors.white70 : Colors.black87),
                          )),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content of Tab
          Expanded(
            child: _leftPaneTab == 0
                ? _buildFieldsTab(context, isDark)
                : _buildObjectsTab(context, isDark),
          ),
        ],
      ),
    );
  }

  // ─── Fields Tab ────────────────────────────────────────────────────────────

  Widget _buildFieldsTab(BuildContext context, bool isDark) {
    final availableTables = widget.tables.isNotEmpty ? widget.tables : [_currentTable];

    var cols = List<ColumnModel>.from(_currentTable.columns);
    if (_fieldSearchQuery.isNotEmpty) {
      cols = cols
          .where((c) =>
              c.displayName.toLowerCase().contains(_fieldSearchQuery.toLowerCase()) ||
              c.name.toLowerCase().contains(_fieldSearchQuery.toLowerCase()))
          .toList();
    }
    if (_sortFieldsAsc) {
      cols.sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Occurrence Selector
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C323D) : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: availableTables.any((t) => t.id == _currentTable.id) ? _currentTable.id : null,
                hint: Text('Current Table ("${_currentTable.displayName}")',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 16),
                items: availableTables.map((t) {
                  return DropdownMenuItem<String>(
                    value: t.id,
                    child: Text('Current Table ("${t.displayName}")',
                        style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final match = availableTables.firstWhere((t) => t.id == id);
                    setState(() => _currentTable = match);
                  }
                },
              ),
            ),
          ),
        ),

        // Search & Sort bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search fields...',
                      hintStyle: const TextStyle(fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      suffixIcon: _fieldSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 12),
                              onPressed: () => setState(() => _fieldSearchQuery = ''),
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 11),
                    onChanged: (v) => setState(() => _fieldSearchQuery = v),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: _sortFieldsAsc ? 'Original Field Order' : 'Sort A to Z',
                child: IconButton(
                  icon: Icon(_sortFieldsAsc ? Icons.sort_by_alpha : Icons.sort, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _sortFieldsAsc = !_sortFieldsAsc),
                ),
              ),
            ],
          ),
        ),

        // Fields Header: Name | Type
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: isDark ? const Color(0xFF262C36) : Colors.grey.shade200,
          child: const Row(
            children: [
              Expanded(child: Text('Name', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              Text('Type', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        // Fields List with Drag support
        Expanded(
          child: ListView.builder(
            itemCount: cols.length,
            itemBuilder: (ctx, idx) {
              final col = cols[idx];
              return Draggable<ColumnModel>(
                data: col,
                feedback: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E88E5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _fieldIconWidget(col.fieldType, isSelected: true),
                        const SizedBox(width: 6),
                        Text(col.displayName,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: _buildFieldRow(col, isDark),
                ),
                child: InkWell(
                  onTap: () {
                    // Clicking places the field into the body part
                    _placeFieldAt(
                      column: col,
                      pos: Offset(60, _headerPart.height + 40),
                    );
                  },
                  child: _buildFieldRow(col, isDark),
                ),
              );
            },
          ),
        ),

        // Bottom Actions: + New Field & Drag Preferences
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF242A34) : const Color(0xFFF1F1F3),
            border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.add, size: 14, color: Colors.green),
                      label: const Text('New Field', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _showNewFieldDialog,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Drag & Drop Help:\nDrag any field to the canvas to place it at that location with your configured label & control preferences.',
                    child: const Icon(Icons.help_outline, size: 16, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Collapsible Drag Preferences
              InkWell(
                onTap: () => setState(() => _dragPreferencesExpanded = !_dragPreferencesExpanded),
                child: Row(
                  children: [
                    Icon(
                      _dragPreferencesExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const Text('Drag Preferences',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ],
                ),
              ),
              if (_dragPreferencesExpanded) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('Placement:', style: TextStyle(fontSize: 10)),
                    const Spacer(),
                    ChoiceChip(
                      label: const Text('Horiz', style: TextStyle(fontSize: 9)),
                      selected: _dragPlacement == 'horizontal',
                      visualDensity: VisualDensity.compact,
                      onSelected: (s) => setState(() => _dragPlacement = 'horizontal'),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('Vert', style: TextStyle(fontSize: 9)),
                      selected: _dragPlacement == 'vertical',
                      visualDensity: VisualDensity.compact,
                      onSelected: (s) => setState(() => _dragPlacement = 'vertical'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Include Label:', style: TextStyle(fontSize: 10)),
                    const Spacer(),
                    Switch(
                      value: _dragIncludeLabel,
                      onChanged: (v) => setState(() => _dragIncludeLabel = v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('Control Style:', style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _dragControlStyle,
                          isDense: true,
                          style: TextStyle(fontSize: 10, color: isDark ? Colors.white : Colors.black87),
                          items: const [
                            DropdownMenuItem(value: 'edit_box', child: Text('Edit Box')),
                            DropdownMenuItem(value: 'drop_down_list', child: Text('Drop-down List')),
                            DropdownMenuItem(value: 'pop_up_menu', child: Text('Pop-up Menu')),
                            DropdownMenuItem(value: 'checkbox_set', child: Text('Checkbox Set')),
                            DropdownMenuItem(value: 'radio_button_set', child: Text('Radio Button Set')),
                            DropdownMenuItem(value: 'drop_down_calendar', child: Text('Calendar')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _dragControlStyle = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldRow(ColumnModel col, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
      ),
      child: Row(
        children: [
          _fieldIconWidget(col.fieldType),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              col.displayName,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatFieldType(col.fieldType),
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _fieldIconWidget(String type, {bool isSelected = false}) {
    final (symbol, color) = switch (type.toLowerCase()) {
      'varchar' || 'text' || 'string' => ('TT', Colors.blue),
      'int' || 'integer' || 'numeric' || 'decimal' || 'double' => ('#', Colors.deepPurple),
      'date' => ('📅', Colors.teal),
      'time' => ('⏱', Colors.amber.shade800),
      'timestamp' => ('⏱📅', Colors.orange),
      'boolean' => ('☑', Colors.green),
      'json' || 'container' => ('🖼', Colors.indigo),
      _ => ('T', Colors.blueGrey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white24 : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : color,
        ),
      ),
    );
  }

  String _formatFieldType(String type) => switch (type.toLowerCase()) {
        'varchar' || 'text' => 'Text',
        'int' || 'integer' => 'Integer',
        'numeric' || 'decimal' => 'Number',
        'date' => 'Date',
        'time' => 'Time',
        'timestamp' => 'Timestamp',
        'boolean' => 'Boolean',
        'json' => 'Container',
        _ => type,
      };

  // ─── Objects Tab ───────────────────────────────────────────────────────────

  Widget _buildObjectsTab(BuildContext context, bool isDark) {
    var objs = List<LayoutObjectModel>.from(_layout.objects);
    if (_objectSearchQuery.isNotEmpty) {
      objs = objs
          .where((o) =>
              (o.name ?? '').toLowerCase().contains(_objectSearchQuery.toLowerCase()) ||
              o.text.toLowerCase().contains(_objectSearchQuery.toLowerCase()) ||
              (o.fieldBinding?.fieldName ?? '').toLowerCase().contains(_objectSearchQuery.toLowerCase()))
          .toList();
    }

    final headerObjs = objs.where((o) => o.y < _headerPart.height).toList();
    final bodyObjs = objs
        .where((o) => o.y >= _headerPart.height && o.y < _headerPart.height + _bodyPart.height)
        .toList();
    final footerObjs = objs.where((o) => o.y >= _headerPart.height + _bodyPart.height).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: 26,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter objects...',
                hintStyle: const TextStyle(fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 14),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 11),
              onChanged: (v) => setState(() => _objectSearchQuery = v),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              _buildObjectSection('HEADER', headerObjs, isDark),
              _buildObjectSection('BODY', bodyObjs, isDark),
              _buildObjectSection('FOOTER', footerObjs, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildObjectSection(String title, List<LayoutObjectModel> items, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: isDark ? const Color(0xFF262C36) : Colors.grey.shade200,
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${items.length}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('(No objects in this part)',
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
          )
        else
          ...items.map((obj) {
            final isSelected = obj.id == _selectedObjectId;
            final labelText = obj.type == 'field'
                ? ':: ${obj.fieldBinding?.fieldName ?? "field"}'
                : (obj.text.isNotEmpty ? obj.text : obj.type);

            return InkWell(
              onTap: () => setState(() => _selectedObjectId = obj.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1E88E5).withOpacity(0.15)
                      : Colors.transparent,
                  border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
                ),
                child: Row(
                  children: [
                    _objectTypeIcon(obj.type),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        labelText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF1E88E5) : (isDark ? Colors.white : Colors.black87),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${obj.x.round()},${obj.y.round()}',
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 13, color: Colors.red),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(maxWidth: 18, maxHeight: 18),
                      onPressed: () {
                        setState(() {
                          _selectedObjectId = obj.id;
                        });
                        _deleteSelectedObject();
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _objectTypeIcon(String type) => switch (type) {
        'field' => const Icon(Icons.input, size: 13, color: Colors.blue),
        'button' => const Icon(Icons.smart_button, size: 13, color: Colors.indigo),
        'portal' => const Icon(Icons.table_chart, size: 13, color: Colors.teal),
        'rect' || 'rounded_rect' || 'oval' || 'line' => const Icon(Icons.crop_square, size: 13, color: Colors.purple),
        _ => const Icon(Icons.title, size: 13, color: Colors.blueGrey),
      };

  // ─── Center Canvas Area ────────────────────────────────────────────────────

  Widget _buildCanvasArea(BuildContext context, bool isDark) {
    final cursorForTool = _activeTool == LayoutTool.pointer
        ? SystemMouseCursors.basic
        : SystemMouseCursors.precise;

    final totalHeight = _headerPart.height + _bodyPart.height + _footerPart.height;

    return MouseRegion(
      cursor: cursorForTool,
      child: Container(
        color: isDark ? const Color(0xFF171A1E) : const Color(0xFFD6D6D8),
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(120),
          minScale: 0.4,
          maxScale: 2.5,
          panEnabled: _activeTool == LayoutTool.pointer && _selectedObjectId == null,
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FileMaker Part Labels Gutter
                _buildPartLabelsGutter(isDark),
                const SizedBox(width: 2),
                // The Canvas Design Sheet
                DragTarget<ColumnModel>(
                  onAcceptWithDetails: (details) {
                    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                    if (renderBox != null) {
                      final localPos = renderBox.globalToLocal(details.offset);
                      _placeFieldAt(column: details.data, pos: localPos);
                    }
                  },
                  builder: (context, candidateData, rejectedData) {
                    return GestureDetector(
                      key: _canvasKey,
                      onTapDown: (details) {
                        if (_activeTool != LayoutTool.pointer &&
                            _activeTool != LayoutTool.format &&
                            _activeTool != LayoutTool.rotate) {
                          _placeObjectFromTool(details.localPosition);
                        } else {
                          setState(() => _selectedObjectId = null);
                        }
                      },
                      child: Container(
                        width: _layout.width,
                        height: math.max(600.0, totalHeight),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black38),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (_showGrid)
                              CustomPaint(
                                size: Size(_layout.width, totalHeight),
                                painter: _GridPainter(isDark: false),
                              ),
                            // Part Boundaries & Draggable Dividers
                            ..._buildPartDividers(),
                            // Layout Objects
                            ..._layout.objects.map((obj) => _buildCanvasObject(context, obj)),
                            // Live Drag Tooltip
                            if (_resizingPartType != null)
                              Positioned(
                                left: 16,
                                top: switch (_resizingPartType) {
                                  'header' => _headerPart.height + 4,
                                  'body' => _headerPart.height + _bodyPart.height + 4,
                                  _ => _headerPart.height + _bodyPart.height + _footerPart.height + 4,
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E88E5),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                                    ],
                                  ),
                                  child: Text(
                                    '${_resizingPartType!.toUpperCase()}: ${_partResizeCurrentHeight.round()} pt',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── FileMaker Part Labels Gutter (Left Margin) ───────────────────────────

  Widget _buildPartLabelsGutter(bool isDark) {
    return Column(
      children: [
        _partTabWidget('header', _headerPart.height, 'Header'),
        _partTabWidget('body', _bodyPart.height, 'Body'),
        _partTabWidget('footer', _footerPart.height, 'Footer'),
      ],
    );
  }

  Widget _partTabWidget(String partType, double height, String label) {
    final isResizing = _resizingPartType == partType;

    return GestureDetector(
      onDoubleTap: () => _showPartSetupDialog(partType),
      child: Container(
        width: 32,
        height: height,
        decoration: BoxDecoration(
          color: isResizing ? const Color(0xFFBBDEFB) : const Color(0xFFE0E0E0),
          border: Border(
            top: const BorderSide(color: Colors.black26),
            left: const BorderSide(color: Colors.black26),
            bottom: const BorderSide(color: Colors.black38, width: 1.5),
          ),
        ),
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isResizing ? const Color(0xFF0D47A1) : Colors.black87,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Draggable Part Dividers ───────────────────────────────────────────────

  List<Widget> _buildPartDividers() {
    final headerH = _headerPart.height;
    final bodyH = _bodyPart.height;
    final footerH = _footerPart.height;

    return [
      // 1. Header/Body Divider Line
      _dividerLine(
        partType: 'header',
        yOffset: headerH,
        label: 'Header',
      ),
      // 2. Body/Footer Divider Line
      _dividerLine(
        partType: 'body',
        yOffset: headerH + bodyH,
        label: 'Body',
      ),
      // 3. Bottom of Footer Divider Line
      _dividerLine(
        partType: 'footer',
        yOffset: headerH + bodyH + footerH,
        label: 'Footer',
      ),
    ];
  }

  Widget _dividerLine({
    required String partType,
    required double yOffset,
    required String label,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      top: yOffset - 7,
      height: 14,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onPartResizeStart(partType, details),
          onPanUpdate: _onPartResizeUpdate,
          onPanEnd: _onPartResizeEnd,
          onDoubleTap: () => _showPartSetupDialog(partType),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              // Visible horizontal line across canvas
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Container(
                  height: 1.5,
                  color: _resizingPartType == partType
                      ? const Color(0xFF1E88E5)
                      : const Color(0xFF64B5F6).withOpacity(0.8),
                ),
              ),
              // Draggable Handle Tag on the line
              Positioned(
                left: 4,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _resizingPartType == partType ? const Color(0xFF1E88E5) : const Color(0xFFBBDEFB),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFF1976D2), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.drag_handle,
                          size: 10,
                          color: _resizingPartType == partType ? Colors.white : const Color(0xFF0D47A1)),
                      const SizedBox(width: 3),
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _resizingPartType == partType ? Colors.white : const Color(0xFF0D47A1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Interactive Canvas Object with 8-Handle Resizing ──────────────────────

  Widget _buildCanvasObject(BuildContext context, LayoutObjectModel obj) {
    final isSelected = obj.id == _selectedObjectId;

    return Positioned(
      left: obj.x,
      top: obj.y,
      width: obj.width,
      height: obj.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedObjectId = obj.id),
        onPanStart: (details) {
          if (_activeTool != LayoutTool.pointer) return;
          _pushUndoState();
          _dragStart[obj.id] = details.globalPosition;
          _objStartPos[obj.id] = Offset(obj.x, obj.y);
          setState(() => _selectedObjectId = obj.id);
        },
        onPanUpdate: (details) {
          if (_activeTool != LayoutTool.pointer) return;
          final start = _dragStart[obj.id];
          final startPos = _objStartPos[obj.id];
          if (start == null || startPos == null) return;
          final delta = details.globalPosition - start;
          final newX = _snap((startPos.dx + delta.dx).clamp(0.0, _layout.width - obj.width));
          final newY = _snap((startPos.dy + delta.dy).clamp(0.0, 3000.0));
          setState(() {
            _layout = _layout.copyWith(
              objects: _layout.objects.map((o) => o.id == obj.id ? o.copyWith(x: newX, y: newY) : o).toList(),
            );
          });
        },
        onPanEnd: (_) {
          _dragStart.remove(obj.id);
          _objStartPos.remove(obj.id);
          _markLayoutDirty();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Body of the Object
            Positioned.fill(
              child: Container(
                decoration: _objectDecoration(obj, isSelected),
                child: _buildObjectInner(obj),
              ),
            ),
            // 8 Resize Handles when selected
            if (isSelected) ..._buildEightResizeHandles(obj),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEightResizeHandles(LayoutObjectModel obj) {
    const handleSize = 8.0;
    const half = handleSize / 2;

    Widget handle(_ResizeHandle handleType, Alignment alignment, MouseCursor cursor) {
      double? left, right, top, bottom;
      switch (handleType) {
        case _ResizeHandle.topLeft:
          left = -half;
          top = -half;
          break;
        case _ResizeHandle.topCenter:
          left = obj.width / 2 - half;
          top = -half;
          break;
        case _ResizeHandle.topRight:
          right = -half;
          top = -half;
          break;
        case _ResizeHandle.middleRight:
          right = -half;
          top = obj.height / 2 - half;
          break;
        case _ResizeHandle.bottomRight:
          right = -half;
          bottom = -half;
          break;
        case _ResizeHandle.bottomCenter:
          left = obj.width / 2 - half;
          bottom = -half;
          break;
        case _ResizeHandle.bottomLeft:
          left = -half;
          bottom = -half;
          break;
        case _ResizeHandle.middleLeft:
          left = -half;
          top = obj.height / 2 - half;
          break;
      }

      return Positioned(
        left: left,
        right: right,
        top: top,
        bottom: bottom,
        width: handleSize,
        height: handleSize,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _pushUndoState();
              setState(() {
                _activeResizeHandle = handleType;
                _objResizeStart = details.globalPosition;
                _objResizeStartBounds = Rect.fromLTWH(obj.x, obj.y, obj.width, obj.height);
              });
            },
            onPanUpdate: (details) {
              if (_activeResizeHandle != handleType || _objResizeStartBounds == null) return;
              final delta = details.globalPosition - _objResizeStart;
              final b = _objResizeStartBounds!;
              double newX = b.left;
              double newY = b.top;
              double newW = b.width;
              double newH = b.height;

              switch (handleType) {
                case _ResizeHandle.topLeft:
                  newX = _snap(math.min(b.right - 16, b.left + delta.dx));
                  newY = _snap(math.min(b.bottom - 10, b.top + delta.dy));
                  newW = b.right - newX;
                  newH = b.bottom - newY;
                  break;
                case _ResizeHandle.topCenter:
                  newY = _snap(math.min(b.bottom - 10, b.top + delta.dy));
                  newH = b.bottom - newY;
                  break;
                case _ResizeHandle.topRight:
                  newY = _snap(math.min(b.bottom - 10, b.top + delta.dy));
                  newW = _snap(math.max(16.0, b.width + delta.dx));
                  newH = b.bottom - newY;
                  break;
                case _ResizeHandle.middleRight:
                  newW = _snap(math.max(16.0, b.width + delta.dx));
                  break;
                case _ResizeHandle.bottomRight:
                  newW = _snap(math.max(16.0, b.width + delta.dx));
                  newH = _snap(math.max(10.0, b.height + delta.dy));
                  break;
                case _ResizeHandle.bottomCenter:
                  newH = _snap(math.max(10.0, b.height + delta.dy));
                  break;
                case _ResizeHandle.bottomLeft:
                  newX = _snap(math.min(b.right - 16, b.left + delta.dx));
                  newW = b.right - newX;
                  newH = _snap(math.max(10.0, b.height + delta.dy));
                  break;
                case _ResizeHandle.middleLeft:
                  newX = _snap(math.min(b.right - 16, b.left + delta.dx));
                  newW = b.right - newX;
                  break;
              }

              setState(() {
                _layout = _layout.copyWith(
                  objects: _layout.objects
                      .map((o) => o.id == obj.id
                          ? o.copyWith(x: newX, y: newY, width: newW, height: newH)
                          : o)
                      .toList(),
                );
              });
            },
            onPanEnd: (_) {
              setState(() {
                _activeResizeHandle = null;
                _objResizeStartBounds = null;
              });
              _markLayoutDirty();
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5),
                border: Border.all(color: Colors.white, width: 1.2),
                shape: BoxShape.rectangle,
              ),
            ),
          ),
        ),
      );
    }

    return [
      handle(_ResizeHandle.topLeft, Alignment.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
      handle(_ResizeHandle.topCenter, Alignment.topCenter, SystemMouseCursors.resizeUpDown),
      handle(_ResizeHandle.topRight, Alignment.topRight, SystemMouseCursors.resizeUpRightDownLeft),
      handle(_ResizeHandle.middleRight, Alignment.centerRight, SystemMouseCursors.resizeLeftRight),
      handle(_ResizeHandle.bottomRight, Alignment.bottomRight, SystemMouseCursors.resizeUpLeftDownRight),
      handle(_ResizeHandle.bottomCenter, Alignment.bottomCenter, SystemMouseCursors.resizeUpDown),
      handle(_ResizeHandle.bottomLeft, Alignment.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft),
      handle(_ResizeHandle.middleLeft, Alignment.centerLeft, SystemMouseCursors.resizeLeftRight),
    ];
  }

  BoxDecoration _objectDecoration(LayoutObjectModel obj, bool isSelected) {
    Color bg = Colors.transparent;
    if (obj.style.fillColor != null &&
        obj.style.fillColor!.startsWith('#') &&
        obj.style.fillColor!.length >= 7) {
      bg = Color(int.parse('0xFF${obj.style.fillColor!.replaceAll('#', '')}'));
    } else if (obj.type == 'button') {
      bg = const Color(0xFF1E88E5);
    } else if (obj.type == 'portal' || obj.type == 'tab_control' || obj.type == 'chart') {
      bg = const Color(0xFFFAFAFA);
    }

    if (obj.type == 'oval') {
      return BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: isSelected ? const Color(0xFF1E88E5) : _parseBorderColor(obj),
          width: isSelected ? 2.0 : obj.style.borderWidth,
        ),
      );
    }

    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(obj.style.cornerRadius),
      border: Border.all(
        color: isSelected ? const Color(0xFF1E88E5) : _parseBorderColor(obj),
        width: isSelected ? 2.0 : obj.style.borderWidth,
      ),
    );
  }

  Color _parseBorderColor(LayoutObjectModel obj) {
    final bc = obj.style.borderColor;
    if (bc != null && bc.startsWith('#') && bc.length >= 7) {
      return Color(int.parse('0xFF${bc.replaceAll('#', '')}'));
    }
    return Colors.black26;
  }

  Widget _buildObjectInner(LayoutObjectModel obj) {
    switch (obj.type) {
      case 'label':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: _getAlignment(obj.style.textAlign),
            child: Text(
              obj.text.isEmpty ? '(Label)' : obj.text,
              style: TextStyle(
                fontSize: obj.style.fontSize,
                fontWeight: obj.style.fontWeight == 'bold' ? FontWeight.bold : FontWeight.normal,
                color: obj.style.textColor != null && obj.style.textColor!.startsWith('#')
                    ? Color(int.parse('0xFF${obj.style.textColor!.replaceAll('#', '')}'))
                    : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );

      case 'field':
        final cStyle = obj.fieldBinding?.controlStyle ?? 'edit_box';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.black26),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ':: ${obj.fieldBinding?.fieldName ?? "field"}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (cStyle == 'drop_down_list' || cStyle == 'pop_up_menu')
                const Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey)
              else if (cStyle == 'checkbox_set')
                const Icon(Icons.check_box_outlined, size: 14, color: Colors.grey)
              else if (cStyle == 'drop_down_calendar')
                const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
            ],
          ),
        );

      case 'button':
        return Center(
          child: Text(
            obj.text.isEmpty ? 'Button' : obj.text,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        );

      case 'popover_button':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(obj.text.isEmpty ? 'Popover' : obj.text,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        );

      case 'button_bar':
        return Row(
          children: [
            Expanded(child: Center(child: Text('Segment 1', style: const TextStyle(fontSize: 11)))),
            const VerticalDivider(width: 1),
            Expanded(child: Center(child: Text('Segment 2', style: const TextStyle(fontSize: 11)))),
            const VerticalDivider(width: 1),
            Expanded(child: Center(child: Text('Segment 3', style: const TextStyle(fontSize: 11)))),
          ],
        );

      case 'tab_control':
        return Column(
          children: [
            Container(
              height: 24,
              color: Colors.grey.shade200,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    color: Colors.white,
                    child: const Text('Tab 1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    child: const Text('Tab 2', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ],
              ),
            ),
            const Expanded(
              child: Center(
                child: Text('Tab Panel Content', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
            ),
          ],
        );

      case 'portal':
        return Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_rows, size: 13, color: Colors.indigo),
                  const SizedBox(width: 4),
                  Text(obj.text.isNotEmpty ? obj.text : 'Related Portal',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ],
              ),
              const Divider(height: 8),
              const Expanded(
                child: Center(
                  child: Text('Portal rows (Relationship graph binding)',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ),
            ],
          ),
        );

      case 'chart':
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bar_chart, size: 28, color: Colors.indigo),
              const SizedBox(height: 4),
              Text(obj.text.isNotEmpty ? obj.text : 'Chart Object',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        );

      case 'web_viewer':
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              Container(
                height: 20,
                color: Colors.grey.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 12, color: Colors.blue),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(obj.text.isNotEmpty ? obj.text : 'https://...',
                          style: const TextStyle(fontSize: 9, color: Colors.grey),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text('Web Viewer Window', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ),
            ],
          ),
        );

      case 'line':
        return CustomPaint(painter: _LinePainter(color: _parseBorderColor(obj)));

      case 'rect':
      case 'rounded_rect':
      case 'oval':
        return const SizedBox.shrink();

      default:
        return Center(child: Text(obj.type, style: const TextStyle(fontSize: 10)));
    }
  }

  Alignment _getAlignment(String align) => switch (align) {
        'right' => Alignment.centerRight,
        'center' => Alignment.center,
        _ => Alignment.centerLeft,
      };

  // ─── Right Inspector ───────────────────────────────────────────────────────

  Widget _buildRightInspector(BuildContext context, bool isDark) {
    final sel = _selectedObject;
    final bg = isDark ? const Color(0xFF1E232B) : const Color(0xFFF9F9FA);

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inspector 4 Tabs: Position | Styles | Data | Text
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262C36) : const Color(0xFFECEEF1),
              border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
            ),
            child: Row(
              children: [
                _inspectorTabBtn(0, Icons.straighten, 'Position & Geometry', isDark),
                _inspectorTabBtn(1, Icons.palette_outlined, 'Appearance & Styles', isDark),
                _inspectorTabBtn(2, Icons.storage_outlined, 'Data Binding', isDark),
                _inspectorTabBtn(3, Icons.text_fields, 'Typography & Text', isDark),
              ],
            ),
          ),

          Expanded(
            child: sel == null
                ? _buildEmptyInspector(context)
                : _buildActiveInspectorTab(context, sel, isDark),
          ),
        ],
      ),
    );
  }

  Widget _inspectorTabBtn(int index, IconData icon, String tip, bool isDark) {
    final isSelected = _inspectorTab == index;
    return Expanded(
      child: Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => setState(() => _inspectorTab = index),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? (isDark ? const Color(0xFF1E232B) : const Color(0xFFF9F9FA)) : Colors.transparent,
              border: isSelected
                  ? const Border(top: BorderSide(color: Color(0xFF1E88E5), width: 2))
                  : null,
            ),
            child: Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF1E88E5) : (isDark ? Colors.white60 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyInspector(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_outlined, size: 36, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No Object Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            const Text(
              'Click any element on the canvas to inspect its geometry, styling, data binding, and typography.\n\nOr drag parts divider lines to adjust Header, Body, and Footer sizes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.aspect_ratio, size: 14),
              label: const Text('Layout Width Setup', style: TextStyle(fontSize: 11)),
              onPressed: () => _showLayoutWidthDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLayoutWidthDialog(BuildContext context) async {
    final wCtrl = TextEditingController(text: _layout.width.round().toString());
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Canvas Width Setup'),
        content: TextField(
          controller: wCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Width (pt)', border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (res == true) {
      final w = double.tryParse(wCtrl.text);
      if (w != null && w > 200) {
        _pushUndoState();
        setState(() => _layout = _layout.copyWith(width: w));
        _markLayoutDirty();
      }
    }
  }

  Widget _buildActiveInspectorTab(BuildContext context, LayoutObjectModel sel, bool isDark) {
    return switch (_inspectorTab) {
      0 => _buildPositionTab(sel, isDark),
      1 => _buildAppearanceTab(sel, isDark),
      2 => _buildDataTab(sel, isDark),
      _ => _buildTypographyTab(sel, isDark),
    };
  }

  // Tab 0: Position & Geometry
  Widget _buildPositionTab(LayoutObjectModel sel, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Object Type Badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                sel.type.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF1E88E5)),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 14),
              tooltip: 'Duplicate (Cmd+D)',
              onPressed: _duplicateSelectedObject,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
              tooltip: 'Delete',
              onPressed: _deleteSelectedObject,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Position & Coordinates
        _inspectorSectionTitle('POSITION'),
        Row(
          children: [
            _numField('Left (X)', sel.x, (v) => _updateSelected(sel.copyWith(x: v))),
            const SizedBox(width: 8),
            _numField('Top (Y)', sel.y, (v) => _updateSelected(sel.copyWith(y: v))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _numField('Right', sel.x + sel.width, (v) => _updateSelected(sel.copyWith(width: math.max(10, v - sel.x)))),
            const SizedBox(width: 8),
            _numField('Bottom', sel.y + sel.height, (v) => _updateSelected(sel.copyWith(height: math.max(4, v - sel.y)))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _numField('Width', sel.width, (v) => _updateSelected(sel.copyWith(width: math.max(10, v)))),
            const SizedBox(width: 8),
            _numField('Height', sel.height, (v) => _updateSelected(sel.copyWith(height: math.max(4, v)))),
          ],
        ),

        const Divider(height: 24),
        _inspectorSectionTitle('AUTOSIZING (ANCHORS)'),
        _buildAutosizingBox(sel),

        const Divider(height: 24),
        _inspectorSectionTitle('ARRANGE & ALIGN'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _actionBtn(Icons.align_horizontal_left, 'Left', () => _alignSelected('left')),
            _actionBtn(Icons.align_horizontal_center, 'Center', () => _alignSelected('center')),
            _actionBtn(Icons.align_horizontal_right, 'Right', () => _alignSelected('right')),
            _actionBtn(Icons.align_vertical_top, 'Top', () => _alignSelected('top')),
            _actionBtn(Icons.align_vertical_center, 'Middle', () => _alignSelected('middle')),
            _actionBtn(Icons.align_vertical_bottom, 'Bottom', () => _alignSelected('bottom')),
            _actionBtn(Icons.flip_to_front, 'Bring Front', _bringToFront),
            _actionBtn(Icons.flip_to_back, 'Send Back', _sendToBack),
          ],
        ),
      ],
    );
  }

  Widget _buildAutosizingBox(LayoutObjectModel sel) {
    final anchors = sel.anchors ?? {'top': true, 'bottom': false, 'left': true, 'right': false};

    Widget anchorPin(String key, IconData icon) {
      final isPinned = anchors[key] == true;
      return InkWell(
        onTap: () {
          final updated = Map<String, bool>.from(anchors);
          updated[key] = !isPinned;
          _updateSelected(sel.copyWith(anchors: updated));
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isPinned ? const Color(0xFF1E88E5) : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(icon, size: 14, color: isPinned ? Colors.white : Colors.black54),
        ),
      );
    }

    return Center(
      child: Container(
        width: 120,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: 4, child: anchorPin('top', Icons.arrow_upward)),
            Positioned(bottom: 4, child: anchorPin('bottom', Icons.arrow_downward)),
            Positioned(left: 4, child: anchorPin('left', Icons.arrow_back)),
            Positioned(right: 4, child: anchorPin('right', Icons.arrow_forward)),
            Container(
              width: 44,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Center(child: Text('Object', style: TextStyle(fontSize: 8))),
            ),
          ],
        ),
      ),
    );
  }

  // Tab 1: Appearance & Styles
  Widget _buildAppearanceTab(LayoutObjectModel sel, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _inspectorSectionTitle('FILL COLOR'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _colorSwatch(sel, null, 'None / Transparent'),
            _colorSwatch(sel, '#FFFFFF', 'White'),
            _colorSwatch(sel, '#F5F5F7', 'Light Grey'),
            _colorSwatch(sel, '#1E88E5', 'Blue'),
            _colorSwatch(sel, '#0D47A1', 'Navy'),
            _colorSwatch(sel, '#2E7D32', 'Green'),
            _colorSwatch(sel, '#F59E0B', 'Amber'),
            _colorSwatch(sel, '#EF4444', 'Red'),
            _colorSwatch(sel, '#21262D', 'Dark'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Hex:', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: sel.style.fillColor ?? ''),
                decoration: const InputDecoration(hintText: '#FFFFFF', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (v) => _updateSelected(
                  sel.copyWith(style: sel.style.copyWith(fillColor: v.trim().isEmpty ? null : v.trim())),
                ),
              ),
            ),
          ],
        ),

        const Divider(height: 24),
        _inspectorSectionTitle('BORDER & CORNERS'),
        Row(
          children: [
            _numField('Width', sel.style.borderWidth, (v) {
              _updateSelected(sel.copyWith(style: sel.style.copyWith(borderWidth: v)));
            }),
            const SizedBox(width: 8),
            _numField('Radius', sel.style.cornerRadius, (v) {
              _updateSelected(sel.copyWith(style: sel.style.copyWith(cornerRadius: v)));
            }),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Border Color:', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: sel.style.borderColor ?? ''),
                decoration: const InputDecoration(hintText: '#9E9E9E', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (v) => _updateSelected(
                  sel.copyWith(style: sel.style.copyWith(borderColor: v.trim().isEmpty ? null : v.trim())),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _colorSwatch(LayoutObjectModel sel, String? hexColor, String tooltip) {
    final isSelected = sel.style.fillColor == hexColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          _updateSelected(sel.copyWith(style: sel.style.copyWith(fillColor: hexColor)));
        },
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: hexColor != null ? Color(int.parse('0xFF${hexColor.replaceAll('#', '')}')) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? const Color(0xFF1E88E5) : Colors.black26,
              width: isSelected ? 2.5 : 1,
            ),
          ),
          child: hexColor == null
              ? const Icon(Icons.block, size: 14, color: Colors.red)
              : null,
        ),
      ),
    );
  }

  // Tab 2: Data Binding
  Widget _buildDataTab(LayoutObjectModel sel, bool isDark) {
    final cols = _currentTable.columns;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _inspectorSectionTitle('FIELD BINDING'),
        const Text('Table Occurrence:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C323D) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('${_currentTable.displayName} (${_currentTable.name})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),

        const Text('Bound Column:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: sel.fieldBinding?.fieldName,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: cols.map((c) {
            return DropdownMenuItem<String>(
              value: c.name,
              child: Text('${c.displayName} (${c.fieldType})', style: const TextStyle(fontSize: 11)),
            );
          }).toList(),
          onChanged: (f) {
            if (f != null) {
              final existing = sel.fieldBinding ?? const FieldBindingModel(fieldName: '');
              _updateSelected(sel.copyWith(
                fieldBinding: FieldBindingModel(
                  tableOccurrence: _currentTable.name,
                  fieldName: f,
                  controlStyle: existing.controlStyle,
                  allowBrowseEntry: existing.allowBrowseEntry,
                  allowFindEntry: existing.allowFindEntry,
                ),
              ));
            }
          },
        ),

        const Divider(height: 24),
        _inspectorSectionTitle('CONTROL STYLE'),
        DropdownButtonFormField<String>(
          value: sel.fieldBinding?.controlStyle ?? 'edit_box',
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'edit_box', child: Text('Edit Box')),
            DropdownMenuItem(value: 'drop_down_list', child: Text('Drop-down List')),
            DropdownMenuItem(value: 'pop_up_menu', child: Text('Pop-up Menu')),
            DropdownMenuItem(value: 'checkbox_set', child: Text('Checkbox Set')),
            DropdownMenuItem(value: 'radio_button_set', child: Text('Radio Button Set')),
            DropdownMenuItem(value: 'drop_down_calendar', child: Text('Drop-down Calendar')),
          ],
          onChanged: (style) {
            if (style != null && sel.fieldBinding != null) {
              _updateSelected(sel.copyWith(
                fieldBinding: FieldBindingModel(
                  tableOccurrence: sel.fieldBinding!.tableOccurrence,
                  fieldName: sel.fieldBinding!.fieldName,
                  controlStyle: style,
                  allowBrowseEntry: sel.fieldBinding!.allowBrowseEntry,
                  allowFindEntry: sel.fieldBinding!.allowFindEntry,
                ),
              ));
            }
          },
        ),

        const Divider(height: 24),
        _inspectorSectionTitle('BEHAVIOR & ENTRY OPTIONS'),
        CheckboxListTile(
          title: const Text('Allow Browse mode entry', style: TextStyle(fontSize: 11)),
          value: sel.fieldBinding?.allowBrowseEntry ?? true,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            if (sel.fieldBinding != null) {
              _updateSelected(sel.copyWith(
                fieldBinding: FieldBindingModel(
                  tableOccurrence: sel.fieldBinding!.tableOccurrence,
                  fieldName: sel.fieldBinding!.fieldName,
                  controlStyle: sel.fieldBinding!.controlStyle,
                  allowBrowseEntry: v ?? true,
                  allowFindEntry: sel.fieldBinding!.allowFindEntry,
                ),
              ));
            }
          },
        ),
        CheckboxListTile(
          title: const Text('Allow Find mode entry', style: TextStyle(fontSize: 11)),
          value: sel.fieldBinding?.allowFindEntry ?? true,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            if (sel.fieldBinding != null) {
              _updateSelected(sel.copyWith(
                fieldBinding: FieldBindingModel(
                  tableOccurrence: sel.fieldBinding!.tableOccurrence,
                  fieldName: sel.fieldBinding!.fieldName,
                  controlStyle: sel.fieldBinding!.controlStyle,
                  allowBrowseEntry: sel.fieldBinding!.allowBrowseEntry,
                  allowFindEntry: v ?? true,
                ),
              ));
            }
          },
        ),
      ],
    );
  }

  // Tab 3: Typography & Text
  Widget _buildTypographyTab(LayoutObjectModel sel, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _inspectorSectionTitle('LABEL / TEXT CONTENT'),
        TextField(
          controller: TextEditingController(text: sel.text),
          decoration: const InputDecoration(labelText: 'Display Text', isDense: true, border: OutlineInputBorder()),
          onChanged: (v) => _updateSelected(sel.copyWith(text: v)),
        ),

        const Divider(height: 24),
        _inspectorSectionTitle('FONT & SIZE'),
        Row(
          children: [
            _numField('Font Size (pt)', sel.style.fontSize, (v) {
              _updateSelected(sel.copyWith(style: sel.style.copyWith(fontSize: v.clamp(6.0, 72.0))));
            }),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Bold', style: TextStyle(fontSize: 11)),
              selected: sel.style.fontWeight == 'bold',
              onSelected: (b) {
                _updateSelected(sel.copyWith(style: sel.style.copyWith(fontWeight: b ? 'bold' : 'normal')));
              },
            ),
          ],
        ),

        const SizedBox(height: 12),
        _inspectorSectionTitle('ALIGNMENT'),
        Row(
          children: [
            _alignChoice(sel, 'left', Icons.format_align_left),
            _alignChoice(sel, 'center', Icons.format_align_center),
            _alignChoice(sel, 'right', Icons.format_align_right),
            _alignChoice(sel, 'justify', Icons.format_align_justify),
          ],
        ),
      ],
    );
  }

  Widget _alignChoice(LayoutObjectModel sel, String align, IconData icon) {
    final isSel = sel.style.textAlign == align;
    return Expanded(
      child: IconButton(
        icon: Icon(icon, color: isSel ? const Color(0xFF1E88E5) : Colors.grey, size: 18),
        onPressed: () => _updateSelected(sel.copyWith(style: sel.style.copyWith(textAlign: align))),
      ),
    );
  }

  Widget _inspectorSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
        ),
      );

  Widget _numField(String label, double value, ValueChanged<double> onChanged) {
    return Expanded(
      child: TextField(
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        keyboardType: TextInputType.number,
        controller: TextEditingController(text: value.round().toString()),
        onSubmitted: (val) {
          final n = double.tryParse(val);
          if (n != null) onChanged(n);
        },
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onPressed) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 12),
      label: Text(label, style: const TextStyle(fontSize: 10)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      ),
      onPressed: onPressed,
    );
  }

  void _updateSelected(LayoutObjectModel updated) {
    setState(() {
      _layout = _layout.copyWith(
        objects: _layout.objects.map((o) => o.id == updated.id ? updated : o).toList(),
      );
    });
    _markLayoutDirty();
  }

  Widget _buildAutoSaveIndicator() {
    final (color, icon, tip) = switch (_autoSaveStatus) {
      _LayoutSaveStatus.saving => (Colors.blue, Icons.sync, 'Saving layout...'),
      _LayoutSaveStatus.saved => (Colors.green, Icons.cloud_done_outlined, 'Layout auto-saved'),
      _LayoutSaveStatus.dirty => (Colors.orange, Icons.edit_note_outlined, 'Unsaved changes'),
      _LayoutSaveStatus.error => (Colors.red, Icons.cloud_off_outlined, 'Auto-save failed — click Save'),
      _LayoutSaveStatus.idle => (Colors.grey, Icons.cloud_done_outlined, 'Layout saved'),
    };

    return Tooltip(
      message: tip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_autoSaveStatus == _LayoutSaveStatus.saving)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blue),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            switch (_autoSaveStatus) {
              _LayoutSaveStatus.saving => 'Saving...',
              _LayoutSaveStatus.saved => 'Saved',
              _LayoutSaveStatus.dirty => 'Unsaved',
              _LayoutSaveStatus.error => 'Error',
              _LayoutSaveStatus.idle => 'Saved',
            },
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─── Extension for LayoutObjectStyle copyWith ─────────────────────────────────

extension LayoutObjectStyleExtension on LayoutObjectStyle {
  LayoutObjectStyle copyWith({
    String? fillColor,
    String? borderColor,
    double? borderWidth,
    double? cornerRadius,
    double? fontSize,
    String? fontWeight,
    String? textColor,
    String? textAlign,
  }) {
    return LayoutObjectStyle(
      fillColor: fillColor ?? this.fillColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      textColor: textColor ?? this.textColor,
      textAlign: textAlign ?? this.textAlign,
    );
  }
}

// ─── Grid Painter ─────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final bool isDark;
  _GridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.05)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Line Painter ─────────────────────────────────────────────────────────────

class _LinePainter extends CustomPainter {
  final Color color;
  const _LinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.color != color;
}
