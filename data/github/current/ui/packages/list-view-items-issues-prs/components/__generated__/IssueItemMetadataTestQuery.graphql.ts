/**
 * @generated SignedSource<<b437d6f2fa82fb620d3ed594fa556fb5>>
 * @relayHash dbca3271e5def9f701f755adb49c2408
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID dbca3271e5def9f701f755adb49c2408

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueItemMetadataTestQuery$variables = {
  id: string;
};
export type IssueItemMetadataTestQuery$data = {
  readonly data: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueItemMetadata">;
  } | null | undefined;
};
export type IssueItemMetadataTestQuery = {
  response: IssueItemMetadataTestQuery$data;
  variables: IssueItemMetadataTestQuery$variables;
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
v4 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v5 = [
  (v3/*: any*/)
],
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
  "type": "ID"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueItemMetadataTestQuery",
    "selections": [
      {
        "alias": "data",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": [
                  {
                    "kind": "Literal",
                    "name": "assigneePageSize",
                    "value": 10
                  },
                  {
                    "kind": "Literal",
                    "name": "includeReactions",
                    "value": false
                  }
                ],
                "kind": "FragmentSpread",
                "name": "IssueItemMetadata"
              }
            ],
            "type": "Issue",
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssueItemMetadataTestQuery",
    "selections": [
      {
        "alias": "data",
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
                "name": "totalCommentsCount",
                "storageKey": null
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
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "totalCount",
                    "storageKey": null
                  }
                ],
                "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v4/*: any*/),
                    "concreteType": "AssigneeConnection",
                    "kind": "LinkedField",
                    "name": "assignedActors",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "AssigneeEdge",
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
                              (v2/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": (v5/*: any*/),
                                "type": "User",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v5/*: any*/),
                                "type": "Bot",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
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
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v5/*: any*/),
                                "type": "Node",
                                "abstractKey": "__isNode"
                              }
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
                    "storageKey": "assignedActors(first:10)"
                  },
                  {
                    "alias": null,
                    "args": (v4/*: any*/),
                    "filters": null,
                    "handle": "connection",
                    "key": "IssueAssignees_assignedActors",
                    "kind": "LinkedHandle",
                    "name": "assignedActors"
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
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "dbca3271e5def9f701f755adb49c2408",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "data": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "data.__isAssignable": (v6/*: any*/),
        "data.__isNode": (v6/*: any*/),
        "data.__typename": (v6/*: any*/),
        "data.assignedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "data.assignedActors.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "AssigneeEdge"
        },
        "data.assignedActors.edges.cursor": (v6/*: any*/),
        "data.assignedActors.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "data.assignedActors.edges.node.__isActor": (v6/*: any*/),
        "data.assignedActors.edges.node.__isNode": (v6/*: any*/),
        "data.assignedActors.edges.node.__typename": (v6/*: any*/),
        "data.assignedActors.edges.node.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "data.assignedActors.edges.node.id": (v7/*: any*/),
        "data.assignedActors.edges.node.isCopilot": (v8/*: any*/),
        "data.assignedActors.edges.node.login": (v6/*: any*/),
        "data.assignedActors.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "data.assignedActors.pageInfo.endCursor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "data.assignedActors.pageInfo.hasNextPage": (v8/*: any*/),
        "data.closedByPullRequestsReferences": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestConnection"
        },
        "data.closedByPullRequestsReferences.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "data.id": (v7/*: any*/),
        "data.totalCommentsCount": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Int"
        }
      }
    },
    "name": "IssueItemMetadataTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a2e6c1e2ea1cd618bc6e5f29b26fbe9f";

export default node;
