/**
 * @generated SignedSource<<dacbe31afea7a6c57bc19a93f3c47d4d>>
 * @relayHash 4eee355a3ce2446462abf1543e74a104
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4eee355a3ce2446462abf1543e74a104

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneListNoMatchesTestQuery$variables = Record<PropertyKey, never>;
export type MilestoneListNoMatchesTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneList">;
  } | null | undefined;
};
export type MilestoneListNoMatchesTestQuery = {
  response: MilestoneListNoMatchesTestQuery$data;
  variables: MilestoneListNoMatchesTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "123"
  }
],
v1 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
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
  (v1/*: any*/),
  {
    "fields": [
      {
        "kind": "Literal",
        "name": "direction",
        "value": "DESC"
      },
      {
        "kind": "Literal",
        "name": "field",
        "value": "CREATED_AT"
      }
    ],
    "kind": "ObjectValue",
    "name": "orderBy"
  },
  {
    "items": [
      {
        "kind": "Literal",
        "name": "states.0",
        "value": "OPEN"
      }
    ],
    "kind": "ListValue",
    "name": "states"
  }
],
v5 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v6 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
],
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v8 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "MilestoneConnection"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v11 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "MilestoneListNoMatchesTestQuery",
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
                "args": [
                  (v1/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "state",
                    "value": "OPEN"
                  }
                ],
                "kind": "FragmentSpread",
                "name": "MilestoneList"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"123\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "MilestoneListNoMatchesTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
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
                "name": "nameWithOwner",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v4/*: any*/),
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "MilestoneEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Milestone",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v3/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "description",
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
                            "name": "url",
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
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": [
                              (v3/*: any*/)
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "progressPercentage",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "openIssueCount",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "closedIssueCount",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "dueOn",
                            "storageKey": null
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
                "storageKey": "milestones(first:10,orderBy:{\"direction\":\"DESC\",\"field\":\"CREATED_AT\"},states:[\"OPEN\"])"
              },
              {
                "alias": null,
                "args": (v4/*: any*/),
                "filters": [
                  "states",
                  "orderBy"
                ],
                "handle": "connection",
                "key": "MilestoneList_milestones",
                "kind": "LinkedHandle",
                "name": "milestones"
              },
              {
                "alias": "open",
                "args": [
                  (v5/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "states",
                    "value": "OPEN"
                  }
                ],
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": (v6/*: any*/),
                "storageKey": "milestones(first:0,states:\"OPEN\")"
              },
              {
                "alias": "closed",
                "args": [
                  (v5/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "states",
                    "value": "CLOSED"
                  }
                ],
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": (v6/*: any*/),
                "storageKey": "milestones(first:0,states:\"CLOSED\")"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"123\")"
      }
    ]
  },
  "params": {
    "id": "4eee355a3ce2446462abf1543e74a104",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v7/*: any*/),
        "node.closed": (v8/*: any*/),
        "node.closed.totalCount": (v9/*: any*/),
        "node.id": (v10/*: any*/),
        "node.milestones": (v8/*: any*/),
        "node.milestones.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "MilestoneEdge"
        },
        "node.milestones.edges.cursor": (v7/*: any*/),
        "node.milestones.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestones.edges.node.__typename": (v7/*: any*/),
        "node.milestones.edges.node.closedIssueCount": (v9/*: any*/),
        "node.milestones.edges.node.description": (v11/*: any*/),
        "node.milestones.edges.node.dueOn": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "node.milestones.edges.node.id": (v10/*: any*/),
        "node.milestones.edges.node.openIssueCount": (v9/*: any*/),
        "node.milestones.edges.node.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "node.milestones.edges.node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.milestones.edges.node.repository.id": (v10/*: any*/),
        "node.milestones.edges.node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "MilestoneState"
        },
        "node.milestones.edges.node.title": (v7/*: any*/),
        "node.milestones.edges.node.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "node.milestones.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "node.milestones.pageInfo.endCursor": (v11/*: any*/),
        "node.milestones.pageInfo.hasNextPage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "node.nameWithOwner": (v7/*: any*/),
        "node.open": (v8/*: any*/),
        "node.open.totalCount": (v9/*: any*/)
      }
    },
    "name": "MilestoneListNoMatchesTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "fc04f22aa65b444c7baf14223f2d38bf";

export default node;
