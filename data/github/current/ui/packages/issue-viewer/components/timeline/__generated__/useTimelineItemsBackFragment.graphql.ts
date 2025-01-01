/**
 * @generated SignedSource<<186eada7ad5ba1d7ea9f473eacc8cc2b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type useTimelineItemsBackFragment$data = {
  readonly backTimelineItems: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __id: string;
        readonly " $fragmentSpreads": FragmentRefs<"NewIssueTimelineItem">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly pageInfo: {
      readonly hasPreviousPage: boolean;
    };
    readonly totalCount: number;
  };
  readonly id: string;
  readonly " $fragmentType": "useTimelineItemsBackFragment";
};
export type useTimelineItemsBackFragment$key = {
  readonly " $data"?: useTimelineItemsBackFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"useTimelineItemsBackFragment">;
};

const node: ReaderFragment = (function(){
var v0 = [
  "backTimelineItems"
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
v3 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
    "storageKey": null
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = [
  (v4/*: any*/)
],
v6 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": (v5/*: any*/),
    "storageKey": null
  }
],
v7 = {
  "kind": "InlineFragment",
  "selections": (v5/*: any*/),
  "type": "User",
  "abstractKey": null
},
v8 = {
  "kind": "InlineFragment",
  "selections": (v5/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v9 = {
  "kind": "InlineFragment",
  "selections": (v5/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v10 = {
  "kind": "InlineFragment",
  "selections": (v5/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v11 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": (v5/*: any*/),
    "storageKey": null
  }
],
v12 = {
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
      "name": "count"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "cursor"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "count",
        "cursor": "cursor",
        "direction": "backward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": null,
        "backward": {
          "count": "count",
          "cursor": "cursor"
        },
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": require('./NewTimelinePaginationBackQuery.graphql'),
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "useTimelineItemsBackFragment",
  "selections": [
    {
      "alias": "backTimelineItems",
      "args": [
        {
          "kind": "Literal",
          "name": "visibleEventsOnly",
          "value": true
        }
      ],
      "concreteType": "IssueTimelineItemsConnection",
      "kind": "LinkedField",
      "name": "__Issue__backTimelineItems_connection",
      "plural": false,
      "selections": [
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
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "totalCount",
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
                  "name": "NewIssueTimelineItem",
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
                          "selections": (v3/*: any*/),
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
                              "selections": (v3/*: any*/),
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
                      "selections": (v6/*: any*/),
                      "type": "LabeledEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v6/*: any*/),
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
                            (v7/*: any*/),
                            (v8/*: any*/),
                            (v9/*: any*/),
                            (v10/*: any*/)
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
                            (v7/*: any*/),
                            (v8/*: any*/),
                            (v9/*: any*/),
                            (v10/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "UnassignedEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v11/*: any*/),
                      "type": "MilestonedEvent",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v11/*: any*/),
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
                      "name": "AddedToProjectEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "MovedColumnsInProjectEvent"
                    },
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "RemovedFromProjectEvent"
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
                      "name": "ConvertedNoteToIssueEvent"
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
                    (v12/*: any*/)
                  ],
                  "args": null,
                  "argumentDefinitions": []
                },
                (v12/*: any*/),
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
        }
      ],
      "storageKey": "__Issue__backTimelineItems_connection(visibleEventsOnly:true)"
    },
    (v4/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "28435f54baadf7ed30eb606716b23f21";

export default node;
