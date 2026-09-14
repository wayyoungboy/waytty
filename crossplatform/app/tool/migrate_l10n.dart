// One-time AST migration. Only application-authored interface text is selected.
import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

final messages = <String, Set<String>>{};
String quoted(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
bool meaningful(String text) => RegExp(r'[A-Za-z\u3400-\u9fff]').hasMatch(text);

class Migrator extends RecursiveAstVisitor<void> {
  Migrator(this.path, this.source);
  final String path, source;
  final edits = <int, (int, String)>{};
  void add(int offset, int length, String replacement) { edits[offset] = (length, replacement); }
  void remember(String text) { if (meaningful(text)) messages.putIfAbsent(text, () => {}).add(path); }
  String encode(Expression value, {bool argument = false}) {
    if (value is SimpleStringLiteral) {
      remember(value.value);
      return argument ? 'LMessage(${quoted(value.value)}, const [])' : quoted(value.value);
    }
    if (value is StringLiteral) {
      if (value.stringValue != null) {
        remember(value.stringValue!);
        return argument ? 'LMessage(${quoted(value.stringValue!)}, const [])' : quoted(value.stringValue!);
      }
      final template = StringBuffer(); final args = <String>[];
      void part(StringLiteral literal) {
        if (literal is SimpleStringLiteral) { template.write(literal.value); }
        if (literal is AdjacentStrings) { for (final s in literal.strings) { part(s); } }
        if (literal is StringInterpolation) {
          for (final item in literal.elements) {
            if (item is InterpolationString) template.write(item.value);
            if (item is InterpolationExpression) {
              template.write('{${args.length}}');
              final expr = item.expression;
              args.add(expr is ConditionalExpression || expr is StringLiteral ? encode(expr, argument: true) : expr.toSource());
            }
          }
        }
      }
      part(value); remember(template.toString());
      return 'LMessage(${quoted(template.toString())}, [${args.join(', ')}])';
    }
    if (value is ConditionalExpression) {
      return '${value.condition.toSource()} ? ${encode(value.thenExpression, argument: argument)} : ${encode(value.elseExpression, argument: argument)}';
    }
    return argument ? value.toSource() : 'LRaw(${value.toSource()})';
  }

  bool authored(Expression expression) => expression is StringLiteral || expression is ConditionalExpression;

  @override void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'Text' && node.constructorName.name == null && node.argumentList.arguments.isNotEmpty) {
      final first = node.argumentList.arguments.first;
      if (authored(first)) {
        add(node.constructorName.offset, node.constructorName.length, 'LText');
        add(first.offset, first.length, encode(first));
        // Do not visit replaced string expressions (edits would overlap).
        for (final arg in node.argumentList.arguments.skip(1)) { arg.accept(this); }
        return;
      }
    }
    // These local helpers consume authored labels; translate at their Text
    // leaves separately while collecting the original vocabulary here.
    if ({'_Section', '_Row', 'SettingsRow', 'SectionHeader'}.contains(node.constructorName.type.name.lexeme)) {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedExpression && authored(arg.expression)) encode(arg.expression);
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override void visitNamedExpression(NamedExpression node) {
    final owner = node.parent?.parent;
    final ownerName = owner is InstanceCreationExpression ? owner.constructorName.type.name.lexeme
        : owner is MethodInvocation ? owner.methodName.name : '';
    final label = node.name.label.name;
    final helperText = (ownerName.startsWith('_') || {'SettingsRow', 'SectionHeader', 'ConfirmDialog', 'Tooltip', 'TextSpan'}.contains(ownerName)) &&
        {'title', 'label', 'subtitle', 'description', 'hint', 'message', 'text', 'confirmLabel', 'cancelLabel'}.contains(label);
    if ((helperText || {'tooltip', 'hintText', 'labelText', 'helperText', 'errorText'}.contains(label)) && authored(node.expression)) {
      // Context is only available in widget methods or State members.
      if (node.thisOrAncestorOfType<MethodDeclaration>() != null || node.thisOrAncestorOfType<FunctionDeclaration>() != null) {
        add(node.expression.offset, node.expression.length, 'tr(context, ${encode(node.expression)})');
        for (AstNode? parent = node.parent; parent != null; parent = parent.parent) {
          if (parent is InstanceCreationExpression && parent.keyword?.lexeme == 'const') add(parent.keyword!.offset, 5, '');
          if (parent is TypedLiteral && parent.constKeyword != null) add(parent.constKeyword!.offset, 5, '');
          if (parent is VariableDeclarationList && parent.keyword?.lexeme == 'const') add(parent.keyword!.offset, 5, 'final');
        }
        return;
      }
    }
    super.visitNamedExpression(node);
  }

  @override void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'Text' && node.target == null && node.argumentList.arguments.isNotEmpty) {
      final first = node.argumentList.arguments.first;
      if (authored(first)) {
        add(node.methodName.offset, node.methodName.length, 'LText');
        add(first.offset, first.length, encode(first));
        for (final arg in node.argumentList.arguments.skip(1)) { arg.accept(this); }
        return;
      }
    }
    if (RegExp(r'^_(sectionLabel|navItem|section|label|tab|groupRow|protocolTab|stat|field|Row|Section)$').hasMatch(node.methodName.name) || {'SettingsRow', 'SectionHeader'}.contains(node.methodName.name)) {
      for (final arg in node.argumentList.arguments) {
        final expr = arg is NamedExpression ? arg.expression : arg;
        if (authored(expr)) encode(expr);
      }
    }
    super.visitMethodInvocation(node);
  }
}

void main(List<String> args) {
  final previous = File('../packages/waytty_l10n/source_messages.json');
  if (previous.existsSync()) {
    final values = jsonDecode(previous.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in values.entries) { messages[entry.key] = (entry.value as List).cast<String>().toSet(); }
  }
  final roots = ['lib', '../packages/yourssh_snippets/lib', '../packages/yourssh_devops/lib', '../packages/yourssh_web_tools/lib'];
  var changed = 0;
  for (final root in roots) {
    for (final file in Directory(root).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (!source.contains('package:flutter/')) continue;
      final unit = parseString(content: source, throwIfDiagnostics: false).unit;
      final visitor = Migrator(file.path, source); unit.accept(visitor);
      if (visitor.edits.isEmpty) continue;
      var result = source;
      for (final offset in visitor.edits.keys.toList()..sort((a, b) => b.compareTo(a))) {
        final (length, text) = visitor.edits[offset]!;
        result = result.replaceRange(offset, offset + length, text);
      }
      if (!result.contains("import 'package:waytty_l10n/waytty_l10n.dart';")) {
        final import = unit.directives.whereType<ImportDirective>().first;
        result = result.replaceRange(import.offset, import.offset, "import 'package:waytty_l10n/waytty_l10n.dart';\n");
      }
      file.writeAsStringSync(result); changed++;
    }
  }
  final ordered = messages.keys.toList()..sort();
  File('../packages/waytty_l10n/source_messages.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    for (final message in ordered) message: messages[message]!.toList(),
  }));
  stdout.writeln('Migrated $changed files; ${messages.length} interface messages.');
}
