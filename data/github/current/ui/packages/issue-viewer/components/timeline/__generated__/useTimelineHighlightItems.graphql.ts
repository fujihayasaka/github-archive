/**
 * @generated SignedSource<<51a247cce0782628d6ed2ade5a5c2d9c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useTimelineHighlightItems$data = {
  readonly id: string;
  readonly timelineItems: {
    readonly afterFocusCount: number;
    readonly beforeFocusCount: number;
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __id: string;
        readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineItem">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly " $fragmentType": "useTimelineHighlightItems";
};
export type useTimelineHighlightItems$key = {
  readonly " $data"?: useTimelineHighlightItems$data;
  readonly " $fragmentSpreads": FragmentRefs<"useTimelineHighlightItems">;
};

import NewTimelinePaginationHighlightQuery_graphql from './NewTimelinePaginationHighlightQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "timelineItems"
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v4 = [
  (v3/*: any*/)
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v6 = [
  (v5/*: any*/)
],
v7 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": (v6/*: any*/),
    "storageKey": null
  }
],
v8 = {
  "kind": "InlineFragment",
  "selections": (v6/*: any*/),
  "type": "User",
  "abstractKey": null
},
v9 = {
  "kind": "InlineFragment",
  "selections": (v6/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v10 = {
  "kind": "InlineFragment",
  "selections": (v6/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v11 = {
  "kind": "InlineFragment",
  "selections": (v6/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v12 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": (v6/*: any*/),
    "storageKey": null
  }
],
v13 = {
  "kind": "ClientExtension",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__id",
      "storageKey": null
    }
  ]
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "after"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "before"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "focusNeighborCount"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "focusText"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "last"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": null,
        "cursor": null,
        "direction": "bidirectional",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "first",
          "cursor": "after"
        },
        "backward": {
          "count": "last",
          "cursor": "before"
        },
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": NewTimelinePaginationHighlightQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "useTimelineHighlightItems",
  "selections": [
    {
      "alias": "timelineItems",
      "args": null,
      "concreteType": "IssueTimelineItemsConnection",
      "kind": "LinkedField",
      "name": "__timelineBackwards_timelineItems_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "beforeFocusCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "afterFocusCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueTimelineItemsEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineDataFragmentSpread",
                  "name": "IssueTimelineItem",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v2/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "createdAt",
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "actor",
                          "plural": false,
                          "selections": (v4/*: any*/),
                          "storageKey": null
                        }
                      ],
                      "type": "TimelineEvent",
                      "abstractKey": "__isTimelineEvent"
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v2/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "viewerDidAuthor",
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "Issue",
                          "kind": "LinkedField",
                          "name": "issue",
                          "plural": false,
                          "selections": [
                            {
                              "alias": null,
                              "args": null,
                              "concreteType": null,
                              "kind": "LinkedField",
                              "name": "author",
                              "plural": false,
                              "selections": (v4/*: any*/),
                              "storageKey": null
                            }
                          ],
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "author",
                          "plural": false,
                          "selections": [
                            (v3/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "avatarUrl",
                              "storageKey": null
                            },
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "profileUrl",
                              "storageKey": null
                            }
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "IssueComment",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "source",
                          "plural": false,
                          "selections": [
                            (v1/*: any*/)
                          ],
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "willCloseTarget",
                          "storageKey": null
                        }
                      ],
                      "type": "CrossReferencedEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v7/*: any*/),
                      "type": "LabeledEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v7/*: any*/),
                      "type": "UnlabeledEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "assignee",
                          "plural": false,
                          "selections": [
                            (v8/*: any*/),
                            (v9/*: any*/),
                            (v10/*: any*/),
                            (v11/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "AssignedEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "assignee",
                          "plural": false,
                          "selections": [
                            (v1/*: any*/),
                            (v8/*: any*/),
                            (v9/*: any*/),
                            (v10/*: any*/),
                            (v11/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "UnassignedEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v12/*: any*/),
                      "type": "MilestonedEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v12/*: any*/),
                      "type": "DemilestonedEvent",
                      "abstractKey": null
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "IssueComment_issueComment"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "SubscribedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UnsubscribedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "MentionedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ClosedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ReopenedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "LockedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UnlockedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "PinnedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UnpinnedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "LabeledEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "RenamedTitleEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UnlabeledEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UnassignedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "AssignedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "CommentDeletedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UserBlockedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "SubIssueAddedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "SubIssueRemovedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ParentIssueAddedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ParentIssueRemovedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "MilestonedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "DemilestonedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "CrossReferencedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ReferencedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ConnectedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "TransferredEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "DisconnectedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "MarkedAsDuplicateEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "UnmarkedAsDuplicateEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ConvertedToDiscussionEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "AddedToProjectV2Event"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "RemovedFromProjectV2Event"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ProjectV2ItemStatusChangedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ConvertedFromDraftEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "IssueTypeAddedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "IssueTypeRemovedEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "IssueTypeChangedEvent"
                    },
                    (v13/*: any*/)
                  ],
                  "args": null,
                  "argumentDefinitions": []
                },
                (v13/*: any*/),
                (v1/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "cursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "PageInfo",
          "kind": "LinkedField",
          "name": "pageInfo",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "endCursor",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "hasNextPage",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "hasPreviousPage",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "startCursor",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v5/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "70031daa5215ed68dfa4a035788dbe34";

export default node;
