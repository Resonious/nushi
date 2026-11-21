import 'package:nushi/gen/nushi/v1/nushi.pb.dart';

import 'fake_daemon.dart';

// What the pinned plan's tests share (pinned_plan_test.dart, its rules and
// parts; pinned_plan_look_test.dart, the window drawn whole): a turn that
// made a plan and worked on after it.

/// A plan of [steps], each its words and status, as item [id].
Item plan(List<(String, String)> steps, {String id = 'plan'}) => Item(
  id: id,
  kind: ItemKind.ITEM_KIND_PLAN,
  plan: [
    for (final (content, status) in steps)
      PlanEntry(content: content, status: status),
  ],
);

/// Four steps, the third running.
Item runningPlan({String id = 'plan'}) => plan(id: id, [
  ('A cursor in store.ListPosts', 'completed'),
  ('Page the feed handler', 'completed'),
  (
    'Older posts link in every template that renders the feed, the '
        'mobile ones too',
    'in_progress',
  ),
  ('Tests for the cursor and the handler', 'pending'),
]);

/// Twelve steps, the fourth running.
Item longPlan({String id = 'plan'}) => plan(id: id, [
  for (var i = 1; i <= 12; i++)
    (
      i == 7
          ? 'Step $i: move every note that has no date into an archive '
                'folder, and say in the index where each one went'
          : 'Step $i of the long plan',
      i < 4
          ? 'completed'
          : i == 4
          ? 'in_progress'
          : 'pending',
    ),
]);

Item _tool(String id, String title) => Item(
  id: id,
  kind: ItemKind.ITEM_KIND_TOOL_CALL,
  toolKind: 'read',
  title: title,
  status: 'completed',
);

/// A turn: the prompt, some reading, [plan] (a running one unless given),
/// and work after it.
List<Item> planItems({Item? plan}) => [
  Item(
    id: 'u',
    kind: ItemKind.ITEM_KIND_USER_MESSAGE,
    text:
        'Paginate the home feed: 20 a page, and keep the reader’s place '
        'across reloads. Tests too.',
  ),
  _tool('r1', 'Read internal/store/posts.go'),
  _tool('r2', 'Read internal/feed/handler.go'),
  agentSays(
    'm1',
    '`ListPosts` reads the whole table in one query. I’ll give it a keyset '
        'cursor on `(published, id)`, so a post published while someone '
        'reads doesn’t shift the pages.',
  ),
  plan ?? runningPlan(),
  _tool('r3', 'Read internal/store/posts_test.go'),
  _tool('r4', 'Read templates/feed.html'),
  agentSays(
    'm2',
    'The cursor and the handler are done. Now the templates: the feed '
        'renders in three of them, and each needs its Older posts link.',
  ),
  _tool('r5', 'Read templates/mobile/feed.html'),
  agentSays(
    'm3',
    'The mobile template builds its list in a partial of its own, so the '
        'link goes there, under the last post, and only when a cursor came '
        'back with the page.',
  ),
  _tool('r6', 'Read templates/mobile/_posts.html'),
  _tool('r7', 'Read templates/amp/feed.html'),
  agentSays(
    'm4',
    'The AMP one can’t run the script the others use for the link’s '
        'prefetch, so it gets a plain anchor. Writing all three now.',
  ),
  _tool('r8', 'Read templates/base.html'),
];

/// A question the agent waits on.
Item question() => Item(
  id: 'q',
  kind: ItemKind.ITEM_KIND_QUESTION,
  status: 'pending',
  text: 'How should a reader move between pages?',
  fields: [
    Field(
      id: 'how',
      title: 'Paging',
      type: FieldType.FIELD_TYPE_CHOICE,
      description: 'Which control ends the feed?',
      options: [
        Option(id: 'o', name: 'An Older posts link', description: 'One page'),
        Option(id: 's', name: 'Endless scroll'),
        Option(id: 'n', name: 'Numbered pages'),
      ],
    ),
  ],
);
