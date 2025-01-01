/**
 * @generated SignedSource<<6e0dbabead36cf6e4cdce2f5f42d9494>>
 * @relayHash f5692359ca3456b779d6665f27387903
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f5692359ca3456b779d6665f27387903

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
export type PullRequestRowSubscription$variables = {
  pullRequestId: string;
};
export type PullRequestRowSubscription$data = {
  readonly pullRequestInfoForListViewUpdated: {
    readonly commentsUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"PullRequestItemMetadata">;
    } | null | undefined;
    readonly commitChecksUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatusFromPullRequest">;
    } | null | undefined;
    readonly reviewDecisionUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"IssuePullRequestDescription">;
    } | null | undefined;
    readonly statusUpdated: {
      readonly isDraft: boolean;
      readonly state: PullRequestState;
    } | null | undefined;
    readonly titleUpdated: {
      readonly title: string;
      readonly titleHTML: string;
    } | null | undefined;
  };
};
export type PullRequestRowSubscription = {
  response: PullRequestRowSubscription$data;
  variables: PullRequestRowSubscription$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "pullRequestId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "pullRequestId"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v7 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    (v8/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": null
    },
    (v6/*: any*/)
  ],
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v16 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v2/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "url",
        "storageKey": null
      },
      (v6/*: any*/)
    ],
    "storageKey": null
  }
],
v17 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v16/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v16/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "PullRequestRowSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "PullRequestInfoForListViewUpdatedPayload",
        "kind": "LinkedField",
        "name": "pullRequestInfoForListViewUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "titleUpdated",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "statusUpdated",
            "plural": false,
            "selections": [
              (v4/*: any*/),
              (v5/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "commentsUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "PullRequestItemMetadata"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "reviewDecisionUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssuePullRequestDescription"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "commitChecksUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "CheckRunStatusFromPullRequest"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "EventSubscription",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "PullRequestRowSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "PullRequestInfoForListViewUpdatedPayload",
        "kind": "LinkedField",
        "name": "pullRequestInfoForListViewUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "titleUpdated",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/),
              (v6/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "statusUpdated",
            "plural": false,
            "selections": [
              (v4/*: any*/),
              (v5/*: any*/),
              (v6/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "commentsUpdated",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "totalCommentsCount",
                "storageKey": null
              },
              (v6/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v7/*: any*/),
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
                              (v6/*: any*/),
                              (v8/*: any*/),
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
                              (v9/*: any*/)
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
                    "storageKey": "assignees(first:10)"
                  },
                  {
                    "alias": null,
                    "args": (v7/*: any*/),
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
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "reviewDecisionUpdated",
            "plural": false,
            "selections": [
              (v6/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v10/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      (v13/*: any*/),
                      (v14/*: any*/),
                      (v15/*: any*/),
                      {
                        "alias": null,
                        "args": [
                          {
                            "kind": "Literal",
                            "name": "enableDuplicate",
                            "value": true
                          }
                        ],
                        "kind": "ScalarField",
                        "name": "stateReason",
                        "storageKey": "stateReason(enableDuplicate:true)"
                      },
                      (v17/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v10/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      (v13/*: any*/),
                      (v14/*: any*/),
                      (v15/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "reviewDecision",
                        "storageKey": null
                      },
                      (v17/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "commitChecksUpdated",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "StatusCheckRollup",
                "kind": "LinkedField",
                "name": "statusCheckRollup",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
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
                          (v4/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v6/*: any*/)
                ],
                "storageKey": null
              },
              (v6/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "f5692359ca3456b779d6665f27387903",
    "metadata": {},
    "name": "PullRequestRowSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "7997810aa9b64cc2931eccffac774bc1";

export default node;
