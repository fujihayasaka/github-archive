/**
 * @generated SignedSource<<eb4ce8c7baea9ab959c0ae440f028852>>
 * @relayHash fea388e3e62bdb84fcc66fb0a9d806b7
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fea388e3e62bdb84fcc66fb0a9d806b7

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarLazyTestQuery$variables = Record<PropertyKey, never>;
export type IssueSidebarLazyTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarLazySections">;
  } | null | undefined;
};
export type IssueSidebarLazyTestQuery = {
  response: IssueSidebarLazyTestQuery$data;
  variables: IssueSidebarLazyTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "test-id"
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
v13 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
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
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v18 = {
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
v19 = {
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
v20 = {
  "kind": "Literal",
  "name": "first",
  "value": 3
},
v21 = [
  (v20/*: any*/),
  {
    "kind": "Literal",
    "name": "ranked",
    "value": true
  }
],
v22 = [
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
      (v17/*: any*/),
      (v14/*: any*/),
      (v9/*: any*/),
      (v18/*: any*/),
      (v15/*: any*/),
      (v19/*: any*/)
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
v23 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v24 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v25 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v27 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v28 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v31 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v33 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v34 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v35 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v36 = {
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
v37 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v38 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v39 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v40 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v41 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v42 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v43 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v44 = {
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
    "name": "IssueSidebarLazyTestQuery",
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
            "args": null,
            "kind": "FragmentSpread",
            "name": "IssueSidebarLazySections"
          }
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueSidebarLazyTestQuery",
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
                                    "selections": [
                                      (v2/*: any*/)
                                    ],
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
                  (v13/*: any*/),
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
                      (v14/*: any*/),
                      (v9/*: any*/),
                      (v8/*: any*/),
                      (v15/*: any*/),
                      (v16/*: any*/),
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
                  (v13/*: any*/),
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
                      (v15/*: any*/),
                      (v16/*: any*/),
                      (v14/*: any*/),
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
                  (v17/*: any*/),
                  (v14/*: any*/),
                  (v9/*: any*/),
                  (v18/*: any*/),
                  (v15/*: any*/),
                  (v19/*: any*/),
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
                "args": (v21/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
                "plural": false,
                "selections": (v22/*: any*/),
                "storageKey": "blockedBy(first:3,ranked:true)"
              },
              {
                "alias": "topBlocking",
                "args": (v21/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blocking",
                "plural": false,
                "selections": (v22/*: any*/),
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
                "args": [
                  (v13/*: any*/)
                ],
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
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "profileResourcePath",
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
                          {
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
                          }
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
              (v14/*: any*/),
              {
                "alias": null,
                "args": [
                  (v20/*: any*/)
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
                      (v15/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "stateReason",
                        "storageKey": null
                      },
                      (v14/*: any*/),
                      (v18/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "duplicateIssues(first:3)"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ]
  },
  "params": {
    "id": "fea388e3e62bdb84fcc66fb0a9d806b7",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v23/*: any*/),
        "node.closedByPullRequestsReferences": (v24/*: any*/),
        "node.closedByPullRequestsReferences.nodes": (v25/*: any*/),
        "node.closedByPullRequestsReferences.nodes.__typename": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.closedByPullRequestsReferences.nodes.id": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isDraft": (v27/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isInMergeQueue": (v27/*: any*/),
        "node.closedByPullRequestsReferences.nodes.number": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository": (v29/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.id": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.name": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner": (v30/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.id": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.login": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.state": (v31/*: any*/),
        "node.closedByPullRequestsReferences.nodes.title": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.url": (v32/*: any*/),
        "node.databaseId": (v33/*: any*/),
        "node.duplicateIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueConnection"
        },
        "node.duplicateIssues.nodes": (v34/*: any*/),
        "node.duplicateIssues.nodes.id": (v26/*: any*/),
        "node.duplicateIssues.nodes.number": (v28/*: any*/),
        "node.duplicateIssues.nodes.repository": (v29/*: any*/),
        "node.duplicateIssues.nodes.repository.id": (v26/*: any*/),
        "node.duplicateIssues.nodes.repository.nameWithOwner": (v23/*: any*/),
        "node.duplicateIssues.nodes.state": (v35/*: any*/),
        "node.duplicateIssues.nodes.stateReason": (v36/*: any*/),
        "node.duplicateIssues.nodes.title": (v23/*: any*/),
        "node.duplicateIssues.nodes.url": (v32/*: any*/),
        "node.id": (v26/*: any*/),
        "node.issueDependenciesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueDependenciesSummary"
        },
        "node.issueDependenciesSummary.blockedBy": (v28/*: any*/),
        "node.issueDependenciesSummary.blocking": (v28/*: any*/),
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
        "node.linkedBranches.nodes.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref": (v37/*: any*/),
        "node.linkedBranches.nodes.ref.__typename": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests": (v38/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.name": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.repository": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef": (v37/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v38/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v40/*: any*/),
        "node.linkedBranches.nodes.ref.repository.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository.nameWithOwner": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.target": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.target.__typename": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.target.id": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.target.oid": (v40/*: any*/),
        "node.linkedPullRequests": (v24/*: any*/),
        "node.linkedPullRequests.nodes": (v25/*: any*/),
        "node.linkedPullRequests.nodes.id": (v26/*: any*/),
        "node.linkedPullRequests.nodes.isDraft": (v27/*: any*/),
        "node.linkedPullRequests.nodes.number": (v28/*: any*/),
        "node.linkedPullRequests.nodes.repository": (v29/*: any*/),
        "node.linkedPullRequests.nodes.repository.id": (v26/*: any*/),
        "node.linkedPullRequests.nodes.repository.name": (v23/*: any*/),
        "node.linkedPullRequests.nodes.repository.nameWithOwner": (v23/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner": (v30/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.__typename": (v23/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.id": (v26/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.login": (v23/*: any*/),
        "node.linkedPullRequests.nodes.state": (v31/*: any*/),
        "node.linkedPullRequests.nodes.url": (v32/*: any*/),
        "node.number": (v28/*: any*/),
        "node.parent": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "node.parent.id": (v26/*: any*/),
        "node.parent.number": (v28/*: any*/),
        "node.parent.repository": (v29/*: any*/),
        "node.parent.repository.id": (v26/*: any*/),
        "node.parent.repository.nameWithOwner": (v23/*: any*/),
        "node.parent.state": (v35/*: any*/),
        "node.parent.stateReason": (v36/*: any*/),
        "node.parent.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "node.parent.subIssuesSummary.completed": (v28/*: any*/),
        "node.parent.subIssuesSummary.total": (v28/*: any*/),
        "node.parent.title": (v23/*: any*/),
        "node.parent.titleHTML": (v23/*: any*/),
        "node.parent.url": (v32/*: any*/),
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
        "node.participants.nodes.__isActor": (v23/*: any*/),
        "node.participants.nodes.__typename": (v23/*: any*/),
        "node.participants.nodes.avatarUrl": (v32/*: any*/),
        "node.participants.nodes.id": (v26/*: any*/),
        "node.participants.nodes.isCopilot": (v27/*: any*/),
        "node.participants.nodes.login": (v23/*: any*/),
        "node.participants.nodes.name": (v41/*: any*/),
        "node.participants.nodes.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.participants.totalCount": (v28/*: any*/),
        "node.repository": (v29/*: any*/),
        "node.repository.databaseId": (v33/*: any*/),
        "node.repository.id": (v26/*: any*/),
        "node.repository.isArchived": (v27/*: any*/),
        "node.repository.name": (v23/*: any*/),
        "node.repository.nameWithOwner": (v23/*: any*/),
        "node.repository.owner": (v30/*: any*/),
        "node.repository.owner.__typename": (v23/*: any*/),
        "node.repository.owner.id": (v26/*: any*/),
        "node.repository.owner.login": (v23/*: any*/),
        "node.repository.viewerCanPinIssues": (v27/*: any*/),
        "node.threadSubscriptionChannel": (v41/*: any*/),
        "node.title": (v23/*: any*/),
        "node.topBlockedBy": (v42/*: any*/),
        "node.topBlockedBy.nodes": (v34/*: any*/),
        "node.topBlockedBy.nodes.id": (v26/*: any*/),
        "node.topBlockedBy.nodes.number": (v28/*: any*/),
        "node.topBlockedBy.nodes.repository": (v29/*: any*/),
        "node.topBlockedBy.nodes.repository.id": (v26/*: any*/),
        "node.topBlockedBy.nodes.repository.nameWithOwner": (v23/*: any*/),
        "node.topBlockedBy.nodes.state": (v35/*: any*/),
        "node.topBlockedBy.nodes.stateReason": (v36/*: any*/),
        "node.topBlockedBy.nodes.title": (v23/*: any*/),
        "node.topBlockedBy.nodes.titleHTML": (v23/*: any*/),
        "node.topBlockedBy.nodes.url": (v32/*: any*/),
        "node.topBlockedBy.pageInfo": (v43/*: any*/),
        "node.topBlockedBy.pageInfo.hasNextPage": (v27/*: any*/),
        "node.topBlocking": (v42/*: any*/),
        "node.topBlocking.nodes": (v34/*: any*/),
        "node.topBlocking.nodes.id": (v26/*: any*/),
        "node.topBlocking.nodes.number": (v28/*: any*/),
        "node.topBlocking.nodes.repository": (v29/*: any*/),
        "node.topBlocking.nodes.repository.id": (v26/*: any*/),
        "node.topBlocking.nodes.repository.nameWithOwner": (v23/*: any*/),
        "node.topBlocking.nodes.state": (v35/*: any*/),
        "node.topBlocking.nodes.stateReason": (v36/*: any*/),
        "node.topBlocking.nodes.title": (v23/*: any*/),
        "node.topBlocking.nodes.titleHTML": (v23/*: any*/),
        "node.topBlocking.nodes.url": (v32/*: any*/),
        "node.topBlocking.pageInfo": (v43/*: any*/),
        "node.topBlocking.pageInfo.hasNextPage": (v27/*: any*/),
        "node.url": (v32/*: any*/),
        "node.viewerCanConvertToDiscussion": (v44/*: any*/),
        "node.viewerCanDelete": (v27/*: any*/),
        "node.viewerCanLinkBranches": (v27/*: any*/),
        "node.viewerCanLock": (v44/*: any*/),
        "node.viewerCanTransfer": (v27/*: any*/),
        "node.viewerCanType": (v44/*: any*/),
        "node.viewerCanUpdateMetadata": (v44/*: any*/),
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
    "name": "IssueSidebarLazyTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "86ea3015f53a2824d59b090a8ddb32ad";

export default node;
