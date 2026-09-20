import 'package:flutter/material.dart';

/// Plain-language explanation of the app's on-device logic: how it picks a
/// suggested exercise, and how it decides what's trending, stuck, or worth
/// a heads-up. No network calls or ML — everything here is a fixed rule
/// running against your own logged history.
class AlgorithmsInfoScreen extends StatelessWidget {
  const AlgorithmsInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How suggestions work')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            title: 'Suggested next exercise',
            body:
                'Shown as its own category at the top of the exercise list '
                'when you pick a workout day. Looked at in order, using your '
                'last ~8 visits for that day:\n\n'
                '1. If you usually start that day with a particular exercise, '
                'that\'s suggested first.\n'
                '2. Otherwise, if the exercise you just checked off is '
                'usually followed by a specific one, that\'s suggested next.\n'
                '3. Otherwise, any other exercise you commonly do that day '
                'and haven\'t logged yet.\n'
                '4. If everything so far is new or too random to find a '
                'pattern, it falls back to the first not-yet-logged '
                'exercise for that day.\n\n'
                'Ties are broken by whichever happened more recently. Once '
                'shown, the suggestion stays put while you\'re filling in '
                'weights/reps for it — it only moves on once that exercise '
                'is completed or unchecked.',
          ),
          _Section(
            title: 'Trending up / stuck / stable',
            body:
                'Looks at your last 6 logged sessions for an exercise. It '
                'compares the average weight in the more recent half to the '
                'earlier half — a change of roughly 1% or more per session '
                'counts as trending up or down; anything smaller reads as '
                'flat.\n\n'
                'Separately, "stuck" (plateaued) means your last 4 sessions '
                'never beat the weight from the session right before that '
                'window — i.e. 4+ sessions with no new high.',
          ),
          _Section(
            title: 'Reps and sets count too',
            body:
                'Weight isn\'t the whole story. If your weight has plateaued '
                'but you\'re doing more total reps or more sets than before '
                '(same rule: compare the more recent half of your last 6 '
                'sessions to the earlier half), that\'s still genuine '
                'progress — it won\'t be flagged as stuck, and shows up '
                'under "Trending up" instead. Graph tooltips for an exercise '
                'also show a "sets×reps" line so you can see that context '
                'directly on the chart. Reps you mark with the "~" toggle '
                'while logging (meaning "about this many, not exact") still '
                'count normally in every calculation — the marker is only '
                'shown back to you, not treated differently by the '
                'algorithm.',
          ),
          _Section(
            title: 'Body weight is factored in',
            body:
                'If your body weight has been trending down over the same '
                'roughly-8-week window, a flat or slightly-down lifting '
                'weight isn\'t flagged as a stall — a small dip in working '
                'weight while cutting is expected, not a sign of stuck '
                'progress. This only softens an already-flat/-down signal; '
                'it never hides a genuine plateau if your body weight is '
                'steady or increasing.',
          ),
          _Section(
            title: 'When a notification actually shows up',
            body:
                'Right after a workout, you\'re only notified about an '
                'exercise if it\'s either genuinely stuck (a real plateau, '
                'not softened by the volume or body-weight checks above) or '
                'your ratings on it have been dropping — a plain "looks '
                'stable" note is never shown, unless every set has been '
                'hitting the top of its rep range for a few sessions in a '
                'row, in which case you get a "try more weight" nudge '
                'instead. The same box on the home tab shows the same '
                'suggestions for your last few weeks, and you can tap any '
                'row there to see the full card again.',
          ),
          _Section(
            title: 'What it suggests when you\'re stuck',
            body:
                'One specific suggestion is picked per exercise, in this '
                'order:\n\n'
                '• If one particular set is clearly the weak link (its reps '
                'or your feedback on it lag behind your other sets), it '
                'suggests adjusting just that set\'s weight or rep range — '
                'not the whole exercise.\n'
                '• Otherwise, if your recent ratings (how the session felt, '
                'last 3 ratings averaged) have been very low, it suggests a '
                'deload — cut the working weight by about 10% or check your '
                'form.\n'
                '• Otherwise, if you haven\'t changed rep range recently, it '
                'suggests trying a slightly higher rep range for a few '
                'sessions before pushing weight again.\n'
                '• Otherwise (you already tried a rep-range change and '
                'you\'re still stuck), it suggests one specific replacement '
                'exercise for the same muscle group — picked from ones '
                'you\'ve trained least recently, never one you were just '
                'told to swap away from.\n\n'
                'If most of a workout day\'s exercises are stuck at once and '
                'each already has its own suggestion above, you additionally '
                'get a nudge to rework that whole day rather than tweaking '
                'exercises one at a time.\n\n'
                'A suggestion you dismiss with "Not now" won\'t come back for '
                'about 10 days, and only that specific suggestion is '
                'suppressed — an unrelated one for the same exercise can '
                'still show up sooner.',
          ),
          _Section(
            title: 'Suggestions you can act on',
            body:
                'Most suggestions come with a "Do this" button. Tapping it '
                'doesn\'t change anything immediately — it queues the change '
                'for the next time you log that exercise, where it shows up '
                'pre-filled: a specific set\'s weight or rep-range target, a '
                'bumped-up rep range, or a replacement exercise swapped '
                'straight into the day\'s list (with a note that it was '
                'swapped in). A "rework this day" suggestion instead takes '
                'you straight to editing that workout day in Settings.',
          ),
          _Section(
            title: 'Weight units per exercise',
            body:
                'Most exercises track plain weight in kg, but you can mark '
                'one as bodyweight (tracks added weight, defaulting to 0), '
                'timed (plain seconds, e.g. planks or holds), or a custom '
                'unit of your own (e.g. "floors" on a stairmaster) — set '
                'this from Settings → "Exercises" or when first adding the '
                'exercise. Trends and suggestions still work the same way '
                'for every unit ("higher is better"), just labeled and '
                'phrased for the right unit — a bodyweight exercise with '
                'flat added weight but climbing reps still counts as '
                'progress rather than a stall.',
          ),
          _Section(
            title: 'Everything runs on your device',
            body:
                'None of this involves a server or AI model — it\'s fixed '
                'arithmetic over the weights, reps, sets, ratings and body '
                'weight you\'ve logged, computed fresh each time from your '
                'Google Sheet.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
