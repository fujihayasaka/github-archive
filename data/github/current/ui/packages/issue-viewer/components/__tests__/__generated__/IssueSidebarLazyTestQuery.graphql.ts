/**
 * @generated SignedSource<<bb7e592c97b883b2cebd61474768a2ad>>
 * @relayHash 854ab5f249ffaf1f5715bb270d3be122
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 854ab5f249ffaf1f5715bb270d3be122

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
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v18 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v19 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v23 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v25 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v27 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v28 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v32 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v33 = {
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
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "titleHTML",
                    "storageKey": null
                  },
                  (v14/*: any*/),
                  (v9/*: any*/),
                  {
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
                      (v5/*: any*/),
                      (v4/*: any*/),
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
    "id": "854ab5f249ffaf1f5715bb270d3be122",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v17/*: any*/),
        "node.closedByPullRequestsReferences": (v18/*: any*/),
        "node.closedByPullRequestsReferences.nodes": (v19/*: any*/),
        "node.closedByPullRequestsReferences.nodes.__typename": (v17/*: any*/),
        "node.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.closedByPullRequestsReferences.nodes.id": (v20/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isDraft": (v21/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isInMergeQueue": (v21/*: any*/),
        "node.closedByPullRequestsReferences.nodes.number": (v22/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository": (v23/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.id": (v20/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.name": (v17/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v17/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner": (v24/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v17/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.id": (v20/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.login": (v17/*: any*/),
        "node.closedByPullRequestsReferences.nodes.state": (v25/*: any*/),
        "node.closedByPullRequestsReferences.nodes.title": (v17/*: any*/),
        "node.closedByPullRequestsReferences.nodes.url": (v26/*: any*/),
        "node.databaseId": (v27/*: any*/),
        "node.id": (v20/*: any*/),
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
        "node.linkedBranches.nodes.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.__typename": (v17/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v22/*: any*/),
        "node.linkedBranches.nodes.ref.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref.name": (v17/*: any*/),
        "node.linkedBranches.nodes.ref.repository": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef": (v28/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v22/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v17/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v23/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v30/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v17/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.repository.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref.repository.nameWithOwner": (v17/*: any*/),
        "node.linkedBranches.nodes.ref.target": (v30/*: any*/),
        "node.linkedBranches.nodes.ref.target.__typename": (v17/*: any*/),
        "node.linkedBranches.nodes.ref.target.id": (v20/*: any*/),
        "node.linkedBranches.nodes.ref.target.oid": (v31/*: any*/),
        "node.linkedPullRequests": (v18/*: any*/),
        "node.linkedPullRequests.nodes": (v19/*: any*/),
        "node.linkedPullRequests.nodes.id": (v20/*: any*/),
        "node.linkedPullRequests.nodes.isDraft": (v21/*: any*/),
        "node.linkedPullRequests.nodes.number": (v22/*: any*/),
        "node.linkedPullRequests.nodes.repository": (v23/*: any*/),
        "node.linkedPullRequests.nodes.repository.id": (v20/*: any*/),
        "node.linkedPullRequests.nodes.repository.name": (v17/*: any*/),
        "node.linkedPullRequests.nodes.repository.nameWithOwner": (v17/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner": (v24/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.__typename": (v17/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.id": (v20/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.login": (v17/*: any*/),
        "node.linkedPullRequests.nodes.state": (v25/*: any*/),
        "node.linkedPullRequests.nodes.url": (v26/*: any*/),
        "node.number": (v22/*: any*/),
        "node.parent": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "node.parent.id": (v20/*: any*/),
        "node.parent.number": (v22/*: any*/),
        "node.parent.repository": (v23/*: any*/),
        "node.parent.repository.id": (v20/*: any*/),
        "node.parent.repository.nameWithOwner": (v17/*: any*/),
        "node.parent.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "node.parent.stateReason": {
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
        "node.parent.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "node.parent.subIssuesSummary.completed": (v22/*: any*/),
        "node.parent.subIssuesSummary.total": (v22/*: any*/),
        "node.parent.title": (v17/*: any*/),
        "node.parent.titleHTML": (v17/*: any*/),
        "node.parent.url": (v26/*: any*/),
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
        "node.participants.nodes.avatarUrl": (v26/*: any*/),
        "node.participants.nodes.id": (v20/*: any*/),
        "node.participants.nodes.login": (v17/*: any*/),
        "node.participants.nodes.name": (v32/*: any*/),
        "node.participants.totalCount": (v22/*: any*/),
        "node.repository": (v23/*: any*/),
        "node.repository.databaseId": (v27/*: any*/),
        "node.repository.id": (v20/*: any*/),
        "node.repository.isArchived": (v21/*: any*/),
        "node.repository.name": (v17/*: any*/),
        "node.repository.nameWithOwner": (v17/*: any*/),
        "node.repository.owner": (v24/*: any*/),
        "node.repository.owner.__typename": (v17/*: any*/),
        "node.repository.owner.id": (v20/*: any*/),
        "node.repository.owner.login": (v17/*: any*/),
        "node.repository.viewerCanPinIssues": (v21/*: any*/),
        "node.threadSubscriptionChannel": (v32/*: any*/),
        "node.title": (v17/*: any*/),
        "node.viewerCanConvertToDiscussion": (v33/*: any*/),
        "node.viewerCanDelete": (v21/*: any*/),
        "node.viewerCanLinkBranches": (v21/*: any*/),
        "node.viewerCanLock": (v33/*: any*/),
        "node.viewerCanTransfer": (v21/*: any*/),
        "node.viewerCanType": (v33/*: any*/),
        "node.viewerCanUpdateMetadata": (v33/*: any*/),
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

(node as any).hash = "47eaeea5cfbcb14e040416f7aa8688ac";

export default node;
