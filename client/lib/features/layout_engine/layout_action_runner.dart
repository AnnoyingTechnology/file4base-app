import '../../core/api/api_client.dart';
import '../../core/models/script_models.dart';
import 'models/layout_definition.dart';

/// Operations a layout button can trigger in Browse mode. Implemented by the
/// data browser, which owns the current record and the found set.
abstract class LayoutActionHost {
  Future<void> actionNewRecord();
  Future<void> actionDuplicateRecord();
  Future<void> actionDeleteRecord({required bool confirm});
  Future<void> actionCommitRecord();
  Future<void> actionRevertRecord();

  /// [target] is `first`, `previous`, `next`, `last` (English or Spanish
  /// names, as written by the Script Workspace) or a 1-based record number.
  Future<void> actionGoToRecord(String target);
  Future<void> actionEnterFindMode();
  Future<void> actionPerformFind();
  Future<void> actionShowAllRecords();
  Future<void> actionEnterPreviewMode();

  /// Returns false when no layout has that name.
  Future<bool> actionGoToLayout(String layoutName);

  /// Returns false when the current table has no such field.
  Future<bool> actionSetField(String field, String value);
  Future<void> actionShowDialog(String title, String message);
  Future<void> actionOpenUrl(String url);

  /// Resolves `{{field}}`, `{{CurrentDate}}`, ... in a step parameter.
  String actionResolveText(String text);
}

/// Outcome of running a button action. [message] explains why a script
/// stopped early (unsupported step, missing script, ...).
class LayoutActionResult {
  final bool completed;
  final String? message;

  const LayoutActionResult.ok()
      : completed = true,
        message = null;

  const LayoutActionResult.stopped(this.message) : completed = false;
}

/// Runs button actions and stored scripts on the client.
///
/// Scripts run step by step in order. Record, navigation, field and dialog
/// steps are supported; steps that need the calculation engine or the server
/// side script runner (If/Loop, Set Variable, REST calls; roadmap phase 7)
/// stop the script with a message instead of being skipped silently.
class LayoutActionRunner {
  final ApiClient apiClient;
  final LayoutActionHost host;

  static const maxScriptDepth = 8;

  LayoutActionRunner({required this.apiClient, required this.host});

  Future<LayoutActionResult> run(ButtonActionModel action) async {
    if (action.isPerformScript) {
      if (action.scriptId == null && (action.scriptName == null || action.scriptName!.isEmpty)) {
        return const LayoutActionResult.stopped('This button has no script selected.');
      }
      return _performScript(id: action.scriptId, name: action.scriptName, depth: 0);
    }
    final step = action.stepType;
    if (step == null) return const LayoutActionResult.stopped('This button has no step selected.');
    return runStep(step, action.params, depth: 0);
  }

  Future<LayoutActionResult> _performScript({String? id, String? name, required int depth}) async {
    if (depth >= maxScriptDepth) {
      return const LayoutActionResult.stopped('Perform Script is nested too deeply (possible recursion).');
    }
    ScriptModel? script;
    try {
      if (id != null && id.isNotEmpty) {
        script = await apiClient.getScript(id);
      } else {
        final all = await apiClient.listScripts();
        script = all.where((s) => s.name.toLowerCase() == name!.toLowerCase()).firstOrNull;
        if (script != null) script = await apiClient.getScript(script.id);
      }
    } catch (e) {
      return LayoutActionResult.stopped('Could not load script "${name ?? id}": $e');
    }
    if (script == null) return LayoutActionResult.stopped('Script "${name ?? id}" not found.');

    final steps = List<ScriptStepModel>.from(script.steps)..sort((a, b) => a.sequenceIdx.compareTo(b.sequenceIdx));
    for (final step in steps) {
      if (!step.isEnabled) continue;
      if (step.stepType == 'halt_script' || step.stepType == 'exit_script') break;
      final result = await runStep(step.stepType, step.params, depth: depth);
      if (!result.completed) {
        return LayoutActionResult.stopped('Script "${script.name}" stopped at step ${step.sequenceIdx}: ${result.message}');
      }
    }
    return const LayoutActionResult.ok();
  }

  Future<LayoutActionResult> runStep(String stepType, Map<String, dynamic> params, {required int depth}) async {
    String p(String key, [String fallback = '']) => host.actionResolveText(params[key]?.toString() ?? fallback);

    switch (stepType) {
      case 'comment':
        return const LayoutActionResult.ok();
      case 'new_record':
        await host.actionNewRecord();
      case 'duplicate_record':
        await host.actionDuplicateRecord();
      case 'delete_record':
        await host.actionDeleteRecord(confirm: params['dialog'] != false);
      case 'commit_records':
        await host.actionCommitRecord();
      case 'revert_record':
        await host.actionRevertRecord();
      case 'go_to_record':
        await host.actionGoToRecord(p('target', 'next'));
      case 'enter_find_mode':
        await host.actionEnterFindMode();
      case 'perform_find':
        await host.actionPerformFind();
      case 'show_all_records':
        await host.actionShowAllRecords();
      case 'enter_preview_mode':
        await host.actionEnterPreviewMode();
      case 'go_to_layout':
        final layout = p('layout_name');
        if (layout.isEmpty) return const LayoutActionResult.stopped('Go to Layout has no layout selected.');
        if (!await host.actionGoToLayout(layout)) {
          return LayoutActionResult.stopped('Layout "$layout" not found.');
        }
      case 'set_field':
        final field = params['field']?.toString() ?? '';
        if (field.isEmpty) return const LayoutActionResult.stopped('Set Field has no field selected.');
        if (!await host.actionSetField(field, p('value'))) {
          return LayoutActionResult.stopped('Field "$field" is not in this table.');
        }
      case 'show_dialog':
        await host.actionShowDialog(p('title', 'Message'), p('message'));
      case 'open_url':
        final url = p('url');
        if (url.isEmpty) return const LayoutActionResult.stopped('Open URL has no URL.');
        await host.actionOpenUrl(url);
      case 'pause_script':
        final seconds = num.tryParse(params['duration_seconds']?.toString() ?? '') ?? 0;
        if (seconds > 0) await Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));
      case 'perform_script':
        final name = params['script_name']?.toString() ?? '';
        if (name.isEmpty) return const LayoutActionResult.stopped('Perform Script has no script name.');
        return _performScript(name: name, depth: depth + 1);
      default:
        return LayoutActionResult.stopped(
            'step "$stepType" is not supported by the client script runner yet '
            '(it needs the calculation engine / server script runner).');
    }
    return const LayoutActionResult.ok();
  }
}
