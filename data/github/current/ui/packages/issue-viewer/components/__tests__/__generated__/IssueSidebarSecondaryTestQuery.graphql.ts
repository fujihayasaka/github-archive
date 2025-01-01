/**
 * @generated SignedSource<<191d528d3cad7e5a58df137fc8b52919>>
 * @relayHash b66d19f03d64c08b7548706ce933ff47
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b66d19f03d64c08b7548706ce933ff47

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarSecondaryTestQuery$variables = Record<PropertyKey, never>;
export type IssueSidebarSecondaryTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarLazySections" | "IssueSidebarSecondary">;
  } | null | undefined;
};
export type IssueSidebarSecondaryTestQuery = {
  response: IssueSidebarSecondaryTestQuery$data;
  variables: IssueSidebarSecondaryTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "test-id-2"
  }
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
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v1/*: any*/),
    (v5/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "target",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "oid",
      "storageKey": null
    },
    (v2/*: any*/),
    (v1/*: any*/)
  ],
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestConnection",
  "kind": "LinkedField",
  "name": "associatedPullRequests",
  "plural": false,
  "selections": [
    (v11/*: any*/)
  ],
  "storageKey": null
},
v13 = [
  (v2/*: any*/)
],
v14 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v20 = {
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
v21 = {
  "kind": "Literal",
  "name": "first",
  "value": 3
},
v22 = [
  (v21/*: any*/),
  {
    "kind": "Literal",
    "name": "ranked",
    "value": true
  }
],
v23 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v2/*: any*/),
      (v8/*: any*/),
      (v18/*: any*/),
      (v15/*: any*/),
      (v9/*: any*/),
      (v19/*: any*/),
      (v16/*: any*/),
      (v20/*: any*/)
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
        "name": "hasNextPage",
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v24 = [
  (v14/*: any*/)
],
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v26 = {
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
v27 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isCopilot",
      "storageKey": null
    }
  ],
  "type": "Bot",
  "abstractKey": null
},
v28 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v29 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v36 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v39 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v40 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v41 = {
  "enumValues": [
    "COMPLETED",
    "DUPLICATE",
    "NOT_PLANNED",
    "REOPENED"
  ],
  "nullable": true,
  "plural": false,
  "type": "IssueStateReason"
},
v42 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v43 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v44 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v45 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v46 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v47 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v48 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v49 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v50 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueSidebarSecondaryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueSidebarLazySections"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueSidebarSecondary"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id-2\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueSidebarSecondaryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanPinIssues",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v8/*: any*/),
              (v9/*: any*/),
              (v3/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 25
                  }
                ],
                "concreteType": "LinkedBranchConnection",
                "kind": "LinkedField",
                "name": "linkedBranches",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "LinkedBranch",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v2/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Ref",
                        "kind": "LinkedField",
                        "name": "ref",
                        "plural": false,
                        "selections": [
                          (v4/*: any*/),
                          (v2/*: any*/),
                          (v1/*: any*/),
                          (v10/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": [
                              (v2/*: any*/),
                              (v7/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Ref",
                                "kind": "LinkedField",
                                "name": "defaultBranchRef",
                                "plural": false,
                                "selections": [
                                  (v4/*: any*/),
                                  (v2/*: any*/),
                                  (v10/*: any*/),
                                  (v12/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": (v13/*: any*/),
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          (v12/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "linkedBranches(first:25)"
              },
              {
                "alias": null,
                "args": [
                  (v14/*: any*/),
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
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequest",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v2/*: any*/),
                      (v1/*: any*/),
                      (v15/*: any*/),
                      (v9/*: any*/),
                      (v8/*: any*/),
                      (v16/*: any*/),
                      (v17/*: any*/),
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
                        "name": "createdAt",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          (v4/*: any*/),
                          (v7/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "owner",
                            "plural": false,
                            "selections": [
                              (v5/*: any*/),
                              (v1/*: any*/),
                              (v2/*: any*/)
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
                "storageKey": "closedByPullRequestsReferences(first:10,includeClosedPrs:true)"
              },
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v14/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "includeClosedPrs",
                    "value": false
                  },
                  {
                    "kind": "Literal",
                    "name": "orderByState",
                    "value": true
                  }
                ],
                "concreteType": "PullRequestConnection",
                "kind": "LinkedField",
                "name": "closedByPullRequestsReferences",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequest",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v7/*: any*/),
                          (v2/*: any*/),
                          (v4/*: any*/),
                          (v6/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v16/*: any*/),
                      (v17/*: any*/),
                      (v15/*: any*/),
                      (v9/*: any*/),
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "closedByPullRequestsReferences(first:10,includeClosedPrs:false,orderByState:true)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanLinkBranches",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v8/*: any*/),
                  (v18/*: any*/),
                  (v15/*: any*/),
                  (v9/*: any*/),
                  (v19/*: any*/),
                  (v16/*: any*/),
                  (v20/*: any*/),
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
                        "name": "total",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "completed",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": "topBlockedBy",
                "args": (v22/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
                "plural": false,
                "selections": (v23/*: any*/),
                "storageKey": "blockedBy(first:3,ranked:true)"
              },
              {
                "alias": "topBlocking",
                "args": (v22/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blocking",
                "plural": false,
                "selections": (v23/*: any*/),
                "storageKey": "blocking(first:3,ranked:true)"
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueDependenciesSummary",
                "kind": "LinkedField",
                "name": "issueDependenciesSummary",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "blockedBy",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "blocking",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateMetadata",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "threadSubscriptionChannel",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerThreadSubscriptionFormAction",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCustomSubscriptionEvents",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v24/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "participants",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "User",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v2/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v1/*: any*/),
                          (v5/*: any*/),
                          (v4/*: any*/),
                          (v25/*: any*/),
                          (v26/*: any*/),
                          (v27/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      }
                    ],
                    "storageKey": null
                  },
                  (v11/*: any*/)
                ],
                "storageKey": "participants(first:10)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanConvertToDiscussion",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanDelete",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanTransfer",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanType",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanLock",
                "storageKey": null
              },
              (v15/*: any*/),
              {
                "alias": null,
                "args": [
                  (v21/*: any*/)
                ],
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "duplicateIssues",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Issue",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v2/*: any*/),
                      (v9/*: any*/),
                      (v8/*: any*/),
                      (v16/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "stateReason",
                        "storageKey": null
                      },
                      (v15/*: any*/),
                      (v19/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "duplicateIssues(first:3)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isTransferInProgress",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v24/*: any*/),
                "concreteType": "AssigneeConnection",
                "kind": "LinkedField",
                "name": "suggestedActors",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v1/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v2/*: any*/),
                          (v5/*: any*/),
                          (v4/*: any*/),
                          (v25/*: any*/),
                          (v26/*: any*/),
                          (v27/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": (v13/*: any*/),
                        "type": "Node",
                        "abstractKey": "__isNode"
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "suggestedActors(first:10)"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id-2\")"
      }
    ]
  },
  "params": {
    "id": "b66d19f03d64c08b7548706ce933ff47",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v28/*: any*/),
        "node.closedByPullRequestsReferences": (v29/*: any*/),
        "node.closedByPullRequestsReferences.nodes": (v30/*: any*/),
        "node.closedByPullRequestsReferences.nodes.__typename": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.closedByPullRequestsReferences.nodes.id": (v31/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isDraft": (v32/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isInMergeQueue": (v32/*: any*/),
        "node.closedByPullRequestsReferences.nodes.number": (v33/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository": (v34/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.id": (v31/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.name": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner": (v35/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.id": (v31/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.login": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.state": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.title": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.url": (v37/*: any*/),
        "node.databaseId": (v38/*: any*/),
        "node.duplicateIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueConnection"
        },
        "node.duplicateIssues.nodes": (v39/*: any*/),
        "node.duplicateIssues.nodes.id": (v31/*: any*/),
        "node.duplicateIssues.nodes.number": (v33/*: any*/),
        "node.duplicateIssues.nodes.repository": (v34/*: any*/),
        "node.duplicateIssues.nodes.repository.id": (v31/*: any*/),
        "node.duplicateIssues.nodes.repository.nameWithOwner": (v28/*: any*/),
        "node.duplicateIssues.nodes.state": (v40/*: any*/),
        "node.duplicateIssues.nodes.stateReason": (v41/*: any*/),
        "node.duplicateIssues.nodes.title": (v28/*: any*/),
        "node.duplicateIssues.nodes.url": (v37/*: any*/),
        "node.id": (v31/*: any*/),
        "node.isTransferInProgress": (v32/*: any*/),
        "node.issueDependenciesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueDependenciesSummary"
        },
        "node.issueDependenciesSummary.blockedBy": (v33/*: any*/),
        "node.issueDependenciesSummary.blocking": (v33/*: any*/),
        "node.linkedBranches": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "LinkedBranchConnection"
        },
        "node.linkedBranches.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LinkedBranch"
        },
        "node.linkedBranches.nodes.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref": (v42/*: any*/),
        "node.linkedBranches.nodes.ref.__typename": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests": (v43/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v33/*: any*/),
        "node.linkedBranches.nodes.ref.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.name": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.repository": (v34/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef": (v42/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v43/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v33/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v34/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v44/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v45/*: any*/),
        "node.linkedBranches.nodes.ref.repository.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.repository.nameWithOwner": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.target": (v44/*: any*/),
        "node.linkedBranches.nodes.ref.target.__typename": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.target.id": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.target.oid": (v45/*: any*/),
        "node.linkedPullRequests": (v29/*: any*/),
        "node.linkedPullRequests.nodes": (v30/*: any*/),
        "node.linkedPullRequests.nodes.id": (v31/*: any*/),
        "node.linkedPullRequests.nodes.isDraft": (v32/*: any*/),
        "node.linkedPullRequests.nodes.number": (v33/*: any*/),
        "node.linkedPullRequests.nodes.repository": (v34/*: any*/),
        "node.linkedPullRequests.nodes.repository.id": (v31/*: any*/),
        "node.linkedPullRequests.nodes.repository.name": (v28/*: any*/),
        "node.linkedPullRequests.nodes.repository.nameWithOwner": (v28/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner": (v35/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.__typename": (v28/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.id": (v31/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.login": (v28/*: any*/),
        "node.linkedPullRequests.nodes.state": (v36/*: any*/),
        "node.linkedPullRequests.nodes.url": (v37/*: any*/),
        "node.number": (v33/*: any*/),
        "node.parent": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "node.parent.id": (v31/*: any*/),
        "node.parent.number": (v33/*: any*/),
        "node.parent.repository": (v34/*: any*/),
        "node.parent.repository.id": (v31/*: any*/),
        "node.parent.repository.nameWithOwner": (v28/*: any*/),
        "node.parent.state": (v40/*: any*/),
        "node.parent.stateReason": (v41/*: any*/),
        "node.parent.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "node.parent.subIssuesSummary.completed": (v33/*: any*/),
        "node.parent.subIssuesSummary.total": (v33/*: any*/),
        "node.parent.title": (v28/*: any*/),
        "node.parent.titleHTML": (v28/*: any*/),
        "node.parent.url": (v37/*: any*/),
        "node.participants": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "UserConnection"
        },
        "node.participants.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "node.participants.nodes.__isActor": (v28/*: any*/),
        "node.participants.nodes.__typename": (v28/*: any*/),
        "node.participants.nodes.avatarUrl": (v37/*: any*/),
        "node.participants.nodes.id": (v31/*: any*/),
        "node.participants.nodes.isCopilot": (v32/*: any*/),
        "node.participants.nodes.login": (v28/*: any*/),
        "node.participants.nodes.name": (v46/*: any*/),
        "node.participants.nodes.profileResourcePath": (v47/*: any*/),
        "node.participants.totalCount": (v33/*: any*/),
        "node.repository": (v34/*: any*/),
        "node.repository.databaseId": (v38/*: any*/),
        "node.repository.id": (v31/*: any*/),
        "node.repository.isArchived": (v32/*: any*/),
        "node.repository.name": (v28/*: any*/),
        "node.repository.nameWithOwner": (v28/*: any*/),
        "node.repository.owner": (v35/*: any*/),
        "node.repository.owner.__typename": (v28/*: any*/),
        "node.repository.owner.id": (v31/*: any*/),
        "node.repository.owner.login": (v28/*: any*/),
        "node.repository.viewerCanPinIssues": (v32/*: any*/),
        "node.suggestedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "node.suggestedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "node.suggestedActors.nodes.__isActor": (v28/*: any*/),
        "node.suggestedActors.nodes.__isNode": (v28/*: any*/),
        "node.suggestedActors.nodes.__typename": (v28/*: any*/),
        "node.suggestedActors.nodes.avatarUrl": (v37/*: any*/),
        "node.suggestedActors.nodes.id": (v31/*: any*/),
        "node.suggestedActors.nodes.isCopilot": (v32/*: any*/),
        "node.suggestedActors.nodes.login": (v28/*: any*/),
        "node.suggestedActors.nodes.name": (v46/*: any*/),
        "node.suggestedActors.nodes.profileResourcePath": (v47/*: any*/),
        "node.threadSubscriptionChannel": (v46/*: any*/),
        "node.title": (v28/*: any*/),
        "node.topBlockedBy": (v48/*: any*/),
        "node.topBlockedBy.nodes": (v39/*: any*/),
        "node.topBlockedBy.nodes.id": (v31/*: any*/),
        "node.topBlockedBy.nodes.number": (v33/*: any*/),
        "node.topBlockedBy.nodes.repository": (v34/*: any*/),
        "node.topBlockedBy.nodes.repository.id": (v31/*: any*/),
        "node.topBlockedBy.nodes.repository.nameWithOwner": (v28/*: any*/),
        "node.topBlockedBy.nodes.state": (v40/*: any*/),
        "node.topBlockedBy.nodes.stateReason": (v41/*: any*/),
        "node.topBlockedBy.nodes.title": (v28/*: any*/),
        "node.topBlockedBy.nodes.titleHTML": (v28/*: any*/),
        "node.topBlockedBy.nodes.url": (v37/*: any*/),
        "node.topBlockedBy.pageInfo": (v49/*: any*/),
        "node.topBlockedBy.pageInfo.hasNextPage": (v32/*: any*/),
        "node.topBlocking": (v48/*: any*/),
        "node.topBlocking.nodes": (v39/*: any*/),
        "node.topBlocking.nodes.id": (v31/*: any*/),
        "node.topBlocking.nodes.number": (v33/*: any*/),
        "node.topBlocking.nodes.repository": (v34/*: any*/),
        "node.topBlocking.nodes.repository.id": (v31/*: any*/),
        "node.topBlocking.nodes.repository.nameWithOwner": (v28/*: any*/),
        "node.topBlocking.nodes.state": (v40/*: any*/),
        "node.topBlocking.nodes.stateReason": (v41/*: any*/),
        "node.topBlocking.nodes.title": (v28/*: any*/),
        "node.topBlocking.nodes.titleHTML": (v28/*: any*/),
        "node.topBlocking.nodes.url": (v37/*: any*/),
        "node.topBlocking.pageInfo": (v49/*: any*/),
        "node.topBlocking.pageInfo.hasNextPage": (v32/*: any*/),
        "node.url": (v37/*: any*/),
        "node.viewerCanConvertToDiscussion": (v50/*: any*/),
        "node.viewerCanDelete": (v32/*: any*/),
        "node.viewerCanLinkBranches": (v32/*: any*/),
        "node.viewerCanLock": (v50/*: any*/),
        "node.viewerCanTransfer": (v32/*: any*/),
        "node.viewerCanType": (v50/*: any*/),
        "node.viewerCanUpdateMetadata": (v50/*: any*/),
        "node.viewerCustomSubscriptionEvents": {
          "enumValues": [
            "CLOSED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": true,
          "type": "ThreadSubscriptionEvent"
        },
        "node.viewerThreadSubscriptionFormAction": {
          "enumValues": [
            "NONE",
            "SUBSCRIBE",
            "UNSUBSCRIBE"
          ],
          "nullable": true,
          "plural": false,
          "type": "ThreadSubscriptionFormAction"
        }
      }
    },
    "name": "IssueSidebarSecondaryTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "ceea84b9e029fae19b311857fa76fc30";

export default node;
