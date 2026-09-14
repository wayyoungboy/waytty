// Run from crossplatform/app. Checks real UI call sites, not only ARB parity.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const roots = [
  'lib',
  '../packages/yourssh_snippets/lib',
  '../packages/yourssh_devops/lib',
  '../packages/yourssh_web_tools/lib',
];
// Technical labels and language endonyms are intentionally unchanged.
const rawLabels = {'HEX', 'DTR', 'RTS', 'English', '简体中文'};
final findings = <String>{};
late Set<String> catalog;
bool readable(String text) =>
    RegExp(r'[A-Za-z]{2}|[\u3400-\u9fff]').hasMatch(text);

class UiAudit extends RecursiveAstVisitor<void> {
  UiAudit(this.path, this.source);
  final String path, source;

  void issue(AstNode node, String message) {
    final line = '\n'.allMatches(source.substring(0, node.offset)).length + 1;
    findings.add('$path:$line $message');
  }

  void message(Expression expression, {required bool translated}) {
    if (expression is StringLiteral && expression.stringValue != null) {
      final text = expression.stringValue!;
      if (!readable(text) || rawLabels.contains(text)) return;
      if (!translated) {
        issue(expression, 'Raw UI label: ${jsonEncode(text)}');
      } else if (!catalog.contains(text)) {
        issue(expression, 'Missing translation: ${jsonEncode(text)}');
      }
    } else if (expression is ConditionalExpression) {
      message(expression.thenExpression, translated: translated);
      message(expression.elseExpression, translated: translated);
    } else if (expression is BinaryExpression &&
        expression.operator.lexeme == '??') {
      message(expression.leftOperand, translated: translated);
      message(expression.rightOperand, translated: translated);
    } else if (expression is SwitchExpression) {
      for (final item in expression.cases) {
        message(item.expression, translated: translated);
      }
    }
  }

  void call(String name, ArgumentList args) {
    final positional = args.arguments
        .where((a) => a is! NamedExpression)
        .toList();
    if ({'Text', 'SelectableText', 'LText', 'LMessage'}.contains(name) &&
        positional.isNotEmpty) {
      message(positional.first, translated: name.startsWith('L'));
    }
    if (name == 'tr' && positional.length > 1) {
      message(positional[1], translated: true);
    }
    if ({
      'Tab',
      'InputDecoration',
      'Tooltip',
      'IconButton',
      'TextSpan',
    }.contains(name)) {
      for (final argument in args.arguments.whereType<NamedExpression>()) {
        if ({
          'text',
          'tooltip',
          'hintText',
          'labelText',
          'helperText',
          'errorText',
          'message',
          'semanticsLabel',
        }.contains(argument.name.label.name)) {
          message(argument.expression, translated: false);
        }
      }
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    call(node.constructorName.type.name.lexeme, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    call(node.methodName.name, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Built-in extension metadata is rendered indirectly in the manager.
    if (path.endsWith('_plugin.dart') &&
        node.isGetter &&
        {'name', 'description'}.contains(node.name.lexeme) &&
        node.body is ExpressionFunctionBody) {
      message(
        (node.body as ExpressionFunctionBody).expression,
        translated: true,
      );
    }
    super.visitMethodDeclaration(node);
  }
}

void main() {
  catalog =
      (jsonDecode(
                File(
                  '../packages/waytty_l10n/source_messages.json',
                ).readAsStringSync(),
              )
              as Map)
          .keys
          .cast<String>()
          .toSet();
  var files = 0;
  for (final root in roots) {
    for (final file
        in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      parseString(content: source).unit.accept(UiAudit(file.path, source));
      files++;
    }
  }
  if (findings.isNotEmpty) {
    for (final finding in findings.toList()..sort()) {
      stderr.writeln(finding);
    }
    exitCode = 1;
  }
  stdout.writeln(
    'Audited $files Dart files: ${findings.length} localization findings.',
  );
}
