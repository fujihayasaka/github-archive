/**
 * @generated SignedSource<<37cc516835cc5f398d1b4fbaafcd38d8>>
 * @relayHash 7d4d7dde5fd2e5a926c830d73099933b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7d4d7dde5fd2e5a926c830d73099933b

import type { ConcreteRequest } from 'relay-runtime';
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
export type RepositoryPermission = "ADMIN" | "MAINTAIN" | "READ" | "TRIAGE" | "WRITE" | "%future added value";
export type DeletePullRequestReviewCommentInput = {
  clientMutationId?: string | null | undefined;
  id: string;
};
export type deletePullRequestCommentMutation$variables = {
  connections: ReadonlyArray<string>;
  endOid?: string | null | undefined;
  filePath?: string | null | undefined;
  input: DeletePullRequestReviewCommentInput;
  singleCommitOid?: string | null | undefined;
  startOid?: string | null | undefined;
};
export type deletePullRequestCommentMutation$data = {
  readonly deletePullRequestReviewComment: {
    readonly pullRequestReviewComment: {
      readonly id: string;
      readonly pullRequest: {
        readonly author: {
          readonly login: string;
        } | null | undefined;
        readonly comparison: {
          readonly newCommit: {
            readonly oid: any;
          };
          readonly summary: ReadonlyArray<{
            readonly path: string;
          }> | null | undefined;
        } | null | undefined;
        readonly headRefOid: any;
        readonly id: string;
        readonly repository: {
          readonly id: string;
          readonly viewerPermission: RepositoryPermission | null | undefined;
        };
        readonly state: PullRequestState;
        readonly threads: {
          readonly edges: ReadonlyArray<{
            readonly __typename: "PullRequestThreadEdge";
          } | null | undefined> | null | undefined;
          readonly totalCommentsCount: number;
        };
        readonly viewerCanLeaveNonCommentReviews: boolean;
        readonly viewerHasViolatedPushPolicy: boolean | null | undefined;
        readonly viewerPendingReview: {
          readonly comments: {
            readonly totalCount: number;
          };
          readonly id: string;
        } | null | undefined;
      };
      readonly pullRequestReview: {
        readonly pullRequestThreadsAndReplies: {
          readonly edges: ReadonlyArray<{
            readonly __typename: "PullRequestReviewCommentItemEdge";
          } | null | undefined> | null | undefined;
          readonly totalCount: number;
        } | null | undefined;
      } | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type deletePullRequestCommentMutation$rawResponse = {
  readonly deletePullRequestReviewComment: {
    readonly pullRequestReviewComment: {
      readonly id: string;
      readonly pullRequest: {
        readonly author: {
          readonly __typename: string;
          readonly id: string;
          readonly login: string;
        } | null | undefined;
        readonly comparison: {
          readonly newCommit: {
            readonly id: string;
            readonly oid: any;
          };
          readonly summary: ReadonlyArray<{
            readonly path: string;
          }> | null | undefined;
        } | null | undefined;
        readonly headRefOid: any;
        readonly id: string;
        readonly repository: {
          readonly id: string;
          readonly viewerPermission: RepositoryPermission | null | undefined;
        };
        readonly state: PullRequestState;
        readonly threads: {
          readonly edges: ReadonlyArray<{
            readonly __typename: "PullRequestThreadEdge";
            readonly cursor: string;
            readonly node: {
              readonly __typename: "PullRequestThread";
              readonly id: string;
            } | null | undefined;
          } | null | undefined> | null | undefined;
          readonly pageInfo: {
            readonly endCursor: string | null | undefined;
            readonly hasNextPage: boolean;
          };
          readonly totalCommentsCount: number;
        };
        readonly viewerCanLeaveNonCommentReviews: boolean;
        readonly viewerHasViolatedPushPolicy: boolean | null | undefined;
        readonly viewerPendingReview: {
          readonly comments: {
            readonly totalCount: number;
          };
          readonly id: string;
        } | null | undefined;
      };
      readonly pullRequestReview: {
        readonly id: string;
        readonly pullRequestThreadsAndReplies: {
          readonly edges: ReadonlyArray<{
            readonly __typename: "PullRequestReviewCommentItemEdge";
            readonly cursor: string;
            readonly node: {
              readonly __typename: string;
              readonly __isNode: string;
              readonly id: string;
            } | null | undefined;
          } | null | undefined> | null | undefined;
          readonly pageInfo: {
            readonly endCursor: string | null | undefined;
            readonly hasNextPage: boolean;
          };
          readonly totalCount: number;
        } | null | undefined;
      } | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type deletePullRequestCommentMutation = {
  rawResponse: deletePullRequestCommentMutation$rawResponse;
  response: deletePullRequestCommentMutation$data;
  variables: deletePullRequestCommentMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "connections"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "endOid"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "filePath"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "input"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "singleCommitOid"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "startOid"
},
v6 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
  }
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
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
  "name": "headRefOid",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerPermission",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v12 = [
  {
    "kind": "Variable",
    "name": "endOid",
    "variableName": "endOid"
  },
  {
    "kind": "Variable",
    "name": "singleCommitOid",
    "variableName": "singleCommitOid"
  },
  {
    "kind": "Variable",
    "name": "startOid",
    "variableName": "startOid"
  }
],
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "oid",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestSummaryDelta",
  "kind": "LinkedField",
  "name": "summary",
  "plural": true,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "path",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanLeaveNonCommentReviews",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerHasViolatedPushPolicy",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestReview",
  "kind": "LinkedField",
  "name": "viewerPendingReview",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "PullRequestReviewCommentConnection",
      "kind": "LinkedField",
      "name": "comments",
      "plural": false,
      "selections": [
        (v17/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
},
v19 = {
  "kind": "Literal",
  "name": "isPositioned",
  "value": false
},
v20 = {
  "kind": "Variable",
  "name": "path",
  "variableName": "filePath"
},
v21 = {
  "kind": "Literal",
  "name": "subjectType",
  "value": "FILE"
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCommentsCount",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v25 = [
  (v23/*: any*/)
],
v26 = {
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
},
v27 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 50
  },
  (v19/*: any*/),
  (v20/*: any*/),
  (v21/*: any*/)
],
v28 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "deletePullRequestCommentMutation",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "DeletePullRequestReviewCommentPayload",
        "kind": "LinkedField",
        "name": "deletePullRequestReviewComment",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequestReviewComment",
            "kind": "LinkedField",
            "name": "pullRequestReviewComment",
            "plural": false,
            "selections": [
              (v7/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequest",
                "kind": "LinkedField",
                "name": "pullRequest",
                "plural": false,
                "selections": [
                  (v7/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "author",
                    "plural": false,
                    "selections": [
                      (v8/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/),
                  {
                    "alias": null,
                    "args": (v12/*: any*/),
                    "concreteType": "PullRequestComparison",
                    "kind": "LinkedField",
                    "name": "comparison",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Commit",
                        "kind": "LinkedField",
                        "name": "newCommit",
                        "plural": false,
                        "selections": [
                          (v13/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v14/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v15/*: any*/),
                  (v16/*: any*/),
                  (v18/*: any*/),
                  {
                    "alias": "threads",
                    "args": [
                      (v19/*: any*/),
                      (v20/*: any*/),
                      (v21/*: any*/)
                    ],
                    "concreteType": "PullRequestThreadConnection",
                    "kind": "LinkedField",
                    "name": "__SingleFileViewConversation_threads_connection",
                    "plural": false,
                    "selections": [
                      (v22/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestThreadEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          (v23/*: any*/),
                          (v24/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "PullRequestThread",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": (v25/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      },
                      (v26/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequestReview",
                "kind": "LinkedField",
                "name": "pullRequestReview",
                "plural": false,
                "selections": [
                  {
                    "alias": "pullRequestThreadsAndReplies",
                    "args": null,
                    "concreteType": "PullRequestReviewCommentItemConnection",
                    "kind": "LinkedField",
                    "name": "__PullRequestReview_pullRequestThreadsAndReplies_connection",
                    "plural": false,
                    "selections": [
                      (v17/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestReviewCommentItemEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          (v23/*: any*/),
                          (v24/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": (v25/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      },
                      (v26/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v3/*: any*/),
      (v2/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "deletePullRequestCommentMutation",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "DeletePullRequestReviewCommentPayload",
        "kind": "LinkedField",
        "name": "deletePullRequestReviewComment",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequestReviewComment",
            "kind": "LinkedField",
            "name": "pullRequestReviewComment",
            "plural": false,
            "selections": [
              (v7/*: any*/),
              {
                "alias": null,
                "args": null,
                "filters": null,
                "handle": "deleteEdge",
                "key": "",
                "kind": "ScalarHandle",
                "name": "id",
                "handleArgs": [
                  {
                    "kind": "Variable",
                    "name": "connections",
                    "variableName": "connections"
                  }
                ]
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequest",
                "kind": "LinkedField",
                "name": "pullRequest",
                "plural": false,
                "selections": [
                  (v7/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "author",
                    "plural": false,
                    "selections": [
                      (v23/*: any*/),
                      (v8/*: any*/),
                      (v7/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/),
                  {
                    "alias": null,
                    "args": (v12/*: any*/),
                    "concreteType": "PullRequestComparison",
                    "kind": "LinkedField",
                    "name": "comparison",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Commit",
                        "kind": "LinkedField",
                        "name": "newCommit",
                        "plural": false,
                        "selections": [
                          (v13/*: any*/),
                          (v7/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v14/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v15/*: any*/),
                  (v16/*: any*/),
                  (v18/*: any*/),
                  {
                    "alias": null,
                    "args": (v27/*: any*/),
                    "concreteType": "PullRequestThreadConnection",
                    "kind": "LinkedField",
                    "name": "threads",
                    "plural": false,
                    "selections": [
                      (v22/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestThreadEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          (v23/*: any*/),
                          (v24/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "PullRequestThread",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              (v23/*: any*/),
                              (v7/*: any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      },
                      (v26/*: any*/)
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": (v27/*: any*/),
                    "filters": [
                      "isPositioned",
                      "subjectType",
                      "path"
                    ],
                    "handle": "connection",
                    "key": "SingleFileViewConversation_threads",
                    "kind": "LinkedHandle",
                    "name": "threads"
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequestReview",
                "kind": "LinkedField",
                "name": "pullRequestReview",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": (v28/*: any*/),
                    "concreteType": "PullRequestReviewCommentItemConnection",
                    "kind": "LinkedField",
                    "name": "pullRequestThreadsAndReplies",
                    "plural": false,
                    "selections": [
                      (v17/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestReviewCommentItemEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          (v23/*: any*/),
                          (v24/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              (v23/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v7/*: any*/)
                                ],
                                "type": "Node",
                                "abstractKey": "__isNode"
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      },
                      (v26/*: any*/)
                    ],
                    "storageKey": "pullRequestThreadsAndReplies(first:100)"
                  },
                  {
                    "alias": null,
                    "args": (v28/*: any*/),
                    "filters": null,
                    "handle": "connection",
                    "key": "PullRequestReview_pullRequestThreadsAndReplies",
                    "kind": "LinkedHandle",
                    "name": "pullRequestThreadsAndReplies"
                  },
                  (v7/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "7d4d7dde5fd2e5a926c830d73099933b",
    "metadata": {
      "connection": [
        {
          "count": null,
          "cursor": null,
          "direction": "forward",
          "path": [
            "deletePullRequestReviewComment",
            "pullRequestReviewComment",
            "pullRequest",
            "threads"
          ]
        },
        {
          "count": null,
          "cursor": null,
          "direction": "forward",
          "path": [
            "deletePullRequestReviewComment",
            "pullRequestReviewComment",
            "pullRequestReview",
            "pullRequestThreadsAndReplies"
          ]
        }
      ]
    },
    "name": "deletePullRequestCommentMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "5367624e19e47b96a5a192218ad78a46";

export default node;
