import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repraid/modes/rpg/ui/adv_widgets.dart';

void main() {
  // The adventure screen puts the Start button and the how-to rows in one
  // list item; the button must still be its own node for screen readers
  // (and so a tap on its node lands on the button).
  testWidgets('a button is its own accessibility node, not merged with the text around it', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              ActionButton(variant: ActionVariant.pick, label: 'Start', sub: '30 days', onPressed: () {}),
              const SizedBox(height: 24),
              const Row(children: [
                Icon(Icons.directions_walk),
                Expanded(child: Text('On the road, one pushup is one day.')),
              ]),
            ]),
          ),
        ]),
      ),
    ));
    expect(find.bySemanticsLabel('Start, 30 days'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Start.*On the road', dotAll: true)), findsNothing);
    expect(find.bySemanticsLabel('On the road, one pushup is one day.'), findsOneWidget);
    handle.dispose();
  });
}
