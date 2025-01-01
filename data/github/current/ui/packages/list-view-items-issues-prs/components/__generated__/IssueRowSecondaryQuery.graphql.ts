/**
 * @generated SignedSource<<70ffb8e4ebca717d1f4c0ceb103b354b>>
 * @relayHash b2f5f79961cb40f216c39beba9fe9f6e
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b2f5f79961cb40f216c39beba9fe9f6e

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueRowSecondaryQuery$variables = {
  assigneePageSize?: number | null | undefined;
  includeReactions?: boolean | null | undefined;
  nodes: ReadonlyArray<string>;
};
export type IssueRowSecondaryQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly __typename: string;
    readonly id: string;
    readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatusFromPullRequest" | "IssueItemMetadata" | "IssueItemSubIssuesSummary" | "IssueOrPullRequestUnreadIndicator" | "PullRequestItemHeadCommit" | "PullRequestItemMetadata" | "PullRequestRowSecondary">;
  } | null | undefined>;
};
export type IssueRowSecondaryQuery = {
  response: IssueRowSecondaryQuery$data;
  variables: IssueRowSecondaryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": 10,
  "kind": "LocalArgument",
  "name": "assigneePageSize"
},
v1 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "includeReactions"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "nodes"
},
v3 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "nodes"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v6 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "IssueOrPullRequestUnreadIndicator"
},
v7 = [
  {
    "kind": "Variable",
    "name": "assigneePageSize",
    "variableName": "assigneePageSize"
  },
  {
    "kind": "Variable",
    "name": "includeReactions",
    "variableName": "includeReactions"
  }
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCommentsCount",
  "storageKey": null
},
v9 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
],
v10 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "isReadByViewer",
    "storageKey": null
  }
],
v11 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v10/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v10/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v12 = {
  "condition": "includeReactions",
  "kind": "Condition",
  "passingValue": true,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "ReactionGroup",
      "kind": "LinkedField",
      "name": "reactionGroups",
      "plural": true,
      "selections": [
        (v5/*: any*/)
      ],
      "storageKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        {
          "condition": "includeReactions",
          "kind": "Condition",
          "passingValue": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "ReactionGroup",
              "kind": "LinkedField",
              "name": "reactionGroups",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "content",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "ReactorConnection",
                  "kind": "LinkedField",
                  "name": "reactors",
                  "plural": false,
                  "selections": (v9/*: any*/),
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ]
        }
      ],
      "type": "Reactable",
      "abstractKey": "__isReactable"
    }
  ]
},
v13 = [
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "assigneePageSize"
  }
],
v14 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": (v13/*: any*/),
      "concreteType": "UserConnection",
      "kind": "LinkedField",
      "name": "assignees",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "UserEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                (v4/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "login",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": [
                    {
                      "kind": "Literal",
                      "name": "size",
                      "value": 64
                    }
                  ],
                  "kind": "ScalarField",
                  "name": "avatarUrl",
                  "storageKey": "avatarUrl(size:64)"
                },
                (v5/*: any*/)
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
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": (v13/*: any*/),
      "filters": null,
      "handle": "connection",
      "key": "IssueAssignees_assignees",
      "kind": "LinkedHandle",
      "name": "assignees"
    },
    {
      "kind": "TypeDiscriminator",
      "abstractKey": "__isNode"
    }
  ],
  "type": "Assignable",
  "abstractKey": "__isAssignable"
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "concreteType": "StatusCheckRollup",
  "kind": "LinkedField",
  "name": "statusCheckRollup",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "StatusCheckRollupContextConnection",
      "kind": "LinkedField",
      "name": "contexts",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "checkRunCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "CheckRunStateCount",
          "kind": "LinkedField",
          "name": "checkRunCountsByState",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "count",
              "storageKey": null
            },
            (v15/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v4/*: any*/)
  ],
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueRowSecondaryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v4/*: any*/),
          (v5/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v6/*: any*/),
              {
                "args": (v7/*: any*/),
                "kind": "FragmentSpread",
                "name": "IssueItemMetadata"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueItemSubIssuesSummary"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v6/*: any*/),
              {
                "args": (v7/*: any*/),
                "kind": "FragmentSpread",
                "name": "PullRequestItemMetadata"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "PullRequestRowSecondary"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "PullRequestItemHeadCommit"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "CheckRunStatusFromPullRequest"
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*: any*/),
      (v0/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueRowSecondaryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v4/*: any*/),
          (v5/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v8/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 0
                  },
                  {
                    "kind": "Literal",
                    "name": "includeClosedPrs",
                    "value": true
                  }
                ],
                "concreteType": "PullRequestConnection",
                "kind": "LinkedField",
                "name": "closedByPullRequestsReferences",
                "plural": false,
                "selections": (v9/*: any*/),
                "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "SubIssuesSummary",
                "kind": "LinkedField",
                "name": "subIssuesSummary",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "completed",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "percentCompleted",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "total",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v11/*: any*/),
              (v12/*: any*/),
              (v14/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v8/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequestCommit",
                "kind": "LinkedField",
                "name": "headCommit",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Commit",
                    "kind": "LinkedField",
                    "name": "commit",
                    "plural": false,
                    "selections": [
                      (v4/*: any*/),
                      (v16/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v4/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isInMergeQueue",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "reviewDecision",
                "storageKey": null
              },
              (v16/*: any*/),
              (v11/*: any*/),
              (v12/*: any*/),
              (v14/*: any*/)
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "b2f5f79961cb40f216c39beba9fe9f6e",
    "metadata": {},
    "name": "IssueRowSecondaryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "daa4b9db32171f1769fd3f42dc2d8209";

export default node;
