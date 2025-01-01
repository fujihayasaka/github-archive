/**
 * @generated SignedSource<<f387802339dc5ab770a2bc4beaf45dec>>
 * @relayHash ddd62204b8946e25b04d3e58970ae8d5
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID ddd62204b8946e25b04d3e58970ae8d5

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DevelopmentSectionTestQuery$variables = {
  number: number;
  owner: string;
  repo: string;
};
export type DevelopmentSectionTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"DevelopmentSectionFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type DevelopmentSectionTestQuery = {
  response: DevelopmentSectionTestQuery$data;
  variables: DevelopmentSectionTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v9/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v14 = {
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
    (v5/*: any*/),
    (v8/*: any*/)
  ],
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestConnection",
  "kind": "LinkedField",
  "name": "associatedPullRequests",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "totalCount",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v16 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v21 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v22 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v23 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v25 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v27 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v28 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v31 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v33 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
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
    "name": "DevelopmentSectionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "DevelopmentSectionFragment"
              }
            ],
            "storageKey": null
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
      (v1/*: any*/),
      (v2/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "DevelopmentSectionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v5/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/)
                ],
                "storageKey": null
              },
              (v5/*: any*/),
              (v12/*: any*/),
              (v13/*: any*/),
              (v6/*: any*/),
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
                      (v5/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Ref",
                        "kind": "LinkedField",
                        "name": "ref",
                        "plural": false,
                        "selections": [
                          (v7/*: any*/),
                          (v5/*: any*/),
                          (v8/*: any*/),
                          (v14/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": [
                              (v5/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Ref",
                                "kind": "LinkedField",
                                "name": "defaultBranchRef",
                                "plural": false,
                                "selections": [
                                  (v7/*: any*/),
                                  (v5/*: any*/),
                                  (v14/*: any*/),
                                  (v15/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": [
                                      (v5/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          (v15/*: any*/)
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
                  (v16/*: any*/),
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
                      (v5/*: any*/),
                      (v8/*: any*/),
                      (v17/*: any*/),
                      (v13/*: any*/),
                      (v12/*: any*/),
                      (v18/*: any*/),
                      (v19/*: any*/),
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
                          (v5/*: any*/),
                          (v7/*: any*/),
                          (v11/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "owner",
                            "plural": false,
                            "selections": [
                              (v9/*: any*/),
                              (v8/*: any*/),
                              (v5/*: any*/)
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
                  (v16/*: any*/),
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
                          (v11/*: any*/),
                          (v5/*: any*/),
                          (v7/*: any*/),
                          (v10/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v18/*: any*/),
                      (v19/*: any*/),
                      (v17/*: any*/),
                      (v13/*: any*/),
                      (v5/*: any*/)
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
              }
            ],
            "storageKey": null
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "ddd62204b8946e25b04d3e58970ae8d5",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v20/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.closedByPullRequestsReferences": (v21/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes": (v22/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.__typename": (v23/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "repository.issue.closedByPullRequestsReferences.nodes.id": (v20/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.isDraft": (v24/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.isInMergeQueue": (v24/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.number": (v25/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository": (v26/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.id": (v20/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.name": (v23/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v23/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner": (v27/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v23/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.id": (v20/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.login": (v23/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.state": (v28/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.title": (v23/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.url": (v29/*: any*/),
        "repository.issue.databaseId": (v30/*: any*/),
        "repository.issue.id": (v20/*: any*/),
        "repository.issue.linkedBranches": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "LinkedBranchConnection"
        },
        "repository.issue.linkedBranches.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LinkedBranch"
        },
        "repository.issue.linkedBranches.nodes.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref": (v31/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.__typename": (v23/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.associatedPullRequests": (v32/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v25/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.name": (v23/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository": (v26/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef": (v31/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v32/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v25/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v23/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v26/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v33/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v23/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v34/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.nameWithOwner": (v23/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target": (v33/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.__typename": (v23/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.id": (v20/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.oid": (v34/*: any*/),
        "repository.issue.linkedPullRequests": (v21/*: any*/),
        "repository.issue.linkedPullRequests.nodes": (v22/*: any*/),
        "repository.issue.linkedPullRequests.nodes.id": (v20/*: any*/),
        "repository.issue.linkedPullRequests.nodes.isDraft": (v24/*: any*/),
        "repository.issue.linkedPullRequests.nodes.number": (v25/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository": (v26/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.id": (v20/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.name": (v23/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.nameWithOwner": (v23/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner": (v27/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.__typename": (v23/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.id": (v20/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.login": (v23/*: any*/),
        "repository.issue.linkedPullRequests.nodes.state": (v28/*: any*/),
        "repository.issue.linkedPullRequests.nodes.url": (v29/*: any*/),
        "repository.issue.number": (v25/*: any*/),
        "repository.issue.repository": (v26/*: any*/),
        "repository.issue.repository.databaseId": (v30/*: any*/),
        "repository.issue.repository.id": (v20/*: any*/),
        "repository.issue.repository.name": (v23/*: any*/),
        "repository.issue.repository.nameWithOwner": (v23/*: any*/),
        "repository.issue.repository.owner": (v27/*: any*/),
        "repository.issue.repository.owner.__typename": (v23/*: any*/),
        "repository.issue.repository.owner.id": (v20/*: any*/),
        "repository.issue.repository.owner.login": (v23/*: any*/),
        "repository.issue.title": (v23/*: any*/),
        "repository.issue.viewerCanLinkBranches": (v24/*: any*/)
      }
    },
    "name": "DevelopmentSectionTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "7ec52d2268b0293e28e67386d591a56b";

export default node;
