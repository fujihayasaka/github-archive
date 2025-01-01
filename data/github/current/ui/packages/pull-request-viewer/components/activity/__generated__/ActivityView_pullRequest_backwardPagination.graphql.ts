/**
 * @generated SignedSource<<cc9bd297797484e8eea08a4d1d45d977>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ActivityView_pullRequest_backwardPagination$data = {
  readonly backwardTimeline: {
    readonly __id: string;
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __typename: string;
        readonly __id: string;
        readonly author?: {
          readonly avatarUrl: string;
          readonly login: string;
        } | null | undefined;
        readonly databaseId?: number | null | undefined;
        readonly " $fragmentSpreads": FragmentRefs<"BaseRefForcePushedEvent_baseRefForcePushedEvent" | "ClosedEvent" | "HeadRefForcePushedEvent_headRefForcePushedEvent" | "IssueComment_issueComment" | "MergedEvent_mergedEvent" | "PullRequestCommit_pullRequestCommit" | "PullRequestReview_pullRequestReview" | "ReactionViewerRelayGroups" | "ReopenedEvent" | "ReviewDismissedEvent_reviewDismissedEvent" | "ReviewRequestedEvent_reviewRequestedEvent">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly id: string;
  readonly " $fragmentType": "ActivityView_pullRequest_backwardPagination";
};
export type ActivityView_pullRequest_backwardPagination$key = {
  readonly " $data"?: ActivityView_pullRequest_backwardPagination$data;
  readonly " $fragmentSpreads": FragmentRefs<"ActivityView_pullRequest_backwardPagination">;
};

import PullRequestActivityBackwardPaginationQuery_graphql from './PullRequestActivityBackwardPaginationQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "backwardTimeline"
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v2 = {
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
      "name": "cursor"
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
        "count": "last",
        "cursor": "cursor",
        "direction": "backward",
        "path": (v0/*: any*/)
      }
    ],
    "refetch": {
      "connection": {
        "forward": null,
        "backward": {
          "count": "last",
          "cursor": "cursor"
        },
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": PullRequestActivityBackwardPaginationQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "ActivityView_pullRequest_backwardPagination",
  "selections": [
    {
      "alias": "backwardTimeline",
      "args": [
        {
          "kind": "Literal",
          "name": "itemTypes",
          "value": [
            "ISSUE_COMMENT",
            "PULL_REQUEST_REVIEW",
            "PULL_REQUEST_COMMIT",
            "BASE_REF_FORCE_PUSHED_EVENT",
            "HEAD_REF_FORCE_PUSHED_EVENT",
            "CLOSED_EVENT",
            "REOPENED_EVENT",
            "MERGED_EVENT",
            "REVIEW_DISMISSED_EVENT",
            "REVIEW_REQUESTED_EVENT"
          ]
        },
        {
          "kind": "Literal",
          "name": "visibleEventsOnly",
          "value": true
        }
      ],
      "concreteType": "PullRequestTimelineItemsConnection",
      "kind": "LinkedField",
      "name": "__PullRequestTimelineBackwardPagination_backwardTimeline_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "PullRequestTimelineItemsEdge",
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
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "__typename",
                  "storageKey": null
                },
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "IssueComment_issueComment"
                },
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "ReactionViewerRelayGroups"
                },
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "PullRequestReview_pullRequestReview"
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": null,
                      "kind": "LinkedField",
                      "name": "author",
                      "plural": false,
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "login",
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "avatarUrl",
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
                    (v1/*: any*/)
                  ],
                  "type": "PullRequestReview",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "PullRequestCommit_pullRequestCommit"
                    }
                  ],
                  "type": "PullRequestCommit",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "BaseRefForcePushedEvent_baseRefForcePushedEvent"
                    }
                  ],
                  "type": "BaseRefForcePushedEvent",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "HeadRefForcePushedEvent_headRefForcePushedEvent"
                    }
                  ],
                  "type": "HeadRefForcePushedEvent",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ClosedEvent"
                    }
                  ],
                  "type": "ClosedEvent",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ReopenedEvent"
                    }
                  ],
                  "type": "ReopenedEvent",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "MergedEvent_mergedEvent"
                    }
                  ],
                  "type": "MergedEvent",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ReviewDismissedEvent_reviewDismissedEvent"
                    }
                  ],
                  "type": "ReviewDismissedEvent",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v1/*: any*/),
                    {
                      "args": null,
                      "kind": "FragmentSpread",
                      "name": "ReviewRequestedEvent_reviewRequestedEvent"
                    }
                  ],
                  "type": "ReviewRequestedEvent",
                  "abstractKey": null
                },
                (v2/*: any*/)
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
        (v2/*: any*/)
      ],
      "storageKey": "__PullRequestTimelineBackwardPagination_backwardTimeline_connection(itemTypes:[\"ISSUE_COMMENT\",\"PULL_REQUEST_REVIEW\",\"PULL_REQUEST_COMMIT\",\"BASE_REF_FORCE_PUSHED_EVENT\",\"HEAD_REF_FORCE_PUSHED_EVENT\",\"CLOSED_EVENT\",\"REOPENED_EVENT\",\"MERGED_EVENT\",\"REVIEW_DISMISSED_EVENT\",\"REVIEW_REQUESTED_EVENT\"],visibleEventsOnly:true)"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};
})();

(node as any).hash = "b88e02139535afc39cca37f8def02f8c";

export default node;
