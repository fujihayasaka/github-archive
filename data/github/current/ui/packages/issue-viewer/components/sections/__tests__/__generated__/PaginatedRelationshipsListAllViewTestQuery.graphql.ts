/**
 * @generated SignedSource<<faaee61d1d56af04c8b1bcf12d95946f>>
 * @relayHash a6d1a66bfafc860b88eef9eeb66ca1a2
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a6d1a66bfafc860b88eef9eeb66ca1a2

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PaginatedRelationshipsListAllViewTestQuery$variables = {
  id: string;
};
export type PaginatedRelationshipsListAllViewTestQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"PaginatedRelationshipsListAllViewItemFragment">;
  } | null | undefined;
};
export type PaginatedRelationshipsListAllViewTestQuery = {
  response: PaginatedRelationshipsListAllViewTestQuery$data;
  variables: PaginatedRelationshipsListAllViewTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "PaginatedRelationshipsListAllViewTestQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "PaginatedRelationshipsListAllViewItemFragment"
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "PaginatedRelationshipsListAllViewTestQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "url",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "number",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "title",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "titleHTML",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "state",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "stateReason",
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
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "name",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "nameWithOwner",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v4/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 10
                  }
                ],
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": [
                  (v5/*: any*/),
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
                          (v3/*: any*/),
                          (v4/*: any*/),
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
                    "storageKey": null
                  }
                ],
                "storageKey": "assignees(first:10)"
              },
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
                "selections": [
                  (v5/*: any*/)
                ],
                "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "a6d1a66bfafc860b88eef9eeb66ca1a2",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "issue.__typename": (v6/*: any*/),
        "issue.assignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "UserConnection"
        },
        "issue.assignees.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "UserEdge"
        },
        "issue.assignees.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "User"
        },
        "issue.assignees.edges.node.avatarUrl": (v7/*: any*/),
        "issue.assignees.edges.node.id": (v8/*: any*/),
        "issue.assignees.edges.node.login": (v6/*: any*/),
        "issue.assignees.totalCount": (v9/*: any*/),
        "issue.closedByPullRequestsReferences": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestConnection"
        },
        "issue.closedByPullRequestsReferences.totalCount": (v9/*: any*/),
        "issue.id": (v8/*: any*/),
        "issue.number": (v9/*: any*/),
        "issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "issue.repository.id": (v8/*: any*/),
        "issue.repository.name": (v6/*: any*/),
        "issue.repository.nameWithOwner": (v6/*: any*/),
        "issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issue.repository.owner.__typename": (v6/*: any*/),
        "issue.repository.owner.id": (v8/*: any*/),
        "issue.repository.owner.login": (v6/*: any*/),
        "issue.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "issue.stateReason": {
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
        "issue.title": (v6/*: any*/),
        "issue.titleHTML": (v6/*: any*/),
        "issue.url": (v7/*: any*/)
      }
    },
    "name": "PaginatedRelationshipsListAllViewTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "aae5b8330e1789a569e4298743d8b093";

export default node;
