/**
 * @generated SignedSource<<cdbe9f497153d9363eb9f69eeb6d2ac8>>
 * @relayHash 90f1c8a1bc9690ee99273ca5f703bd73
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 90f1c8a1bc9690ee99273ca5f703bd73

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestonesTestQuery$variables = Record<PropertyKey, never>;
export type RepositoryMilestonesTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestonesInternal">;
  } | null | undefined;
};
export type RepositoryMilestonesTestQuery = {
  response: RepositoryMilestonesTestQuery$data;
  variables: RepositoryMilestonesTestQuery$variables;
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
v3 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 50
  },
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
v4 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v5 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
],
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v7 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "MilestoneConnection"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v10 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "RepositoryMilestonesTestQuery",
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
                  {
                    "kind": "Literal",
                    "name": "state",
                    "value": "OPEN"
                  }
                ],
                "kind": "FragmentSpread",
                "name": "RepositoryMilestonesInternal"
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
    "name": "RepositoryMilestonesTestQuery",
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
                "kind": "ScalarField",
                "name": "nameWithOwner",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v3/*: any*/),
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
                          (v2/*: any*/),
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
                              (v2/*: any*/)
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
                          (v1/*: any*/)
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
                "storageKey": "milestones(first:50,orderBy:{\"direction\":\"DESC\",\"field\":\"CREATED_AT\"},states:[\"OPEN\"])"
              },
              {
                "alias": null,
                "args": (v3/*: any*/),
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
                  (v4/*: any*/),
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
                "selections": (v5/*: any*/),
                "storageKey": "milestones(first:0,states:\"OPEN\")"
              },
              {
                "alias": "closed",
                "args": [
                  (v4/*: any*/),
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
                "selections": (v5/*: any*/),
                "storageKey": "milestones(first:0,states:\"CLOSED\")"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanPush",
                "storageKey": null
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
    "id": "90f1c8a1bc9690ee99273ca5f703bd73",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v6/*: any*/),
        "node.closed": (v7/*: any*/),
        "node.closed.totalCount": (v8/*: any*/),
        "node.id": (v9/*: any*/),
        "node.milestones": (v7/*: any*/),
        "node.milestones.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "MilestoneEdge"
        },
        "node.milestones.edges.cursor": (v6/*: any*/),
        "node.milestones.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestones.edges.node.__typename": (v6/*: any*/),
        "node.milestones.edges.node.closedIssueCount": (v8/*: any*/),
        "node.milestones.edges.node.description": (v10/*: any*/),
        "node.milestones.edges.node.dueOn": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "node.milestones.edges.node.id": (v9/*: any*/),
        "node.milestones.edges.node.openIssueCount": (v8/*: any*/),
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
        "node.milestones.edges.node.repository.id": (v9/*: any*/),
        "node.milestones.edges.node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "MilestoneState"
        },
        "node.milestones.edges.node.title": (v6/*: any*/),
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
        "node.milestones.pageInfo.endCursor": (v10/*: any*/),
        "node.milestones.pageInfo.hasNextPage": (v11/*: any*/),
        "node.nameWithOwner": (v6/*: any*/),
        "node.open": (v7/*: any*/),
        "node.open.totalCount": (v8/*: any*/),
        "node.viewerCanPush": (v11/*: any*/)
      }
    },
    "name": "RepositoryMilestonesTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "cba1258acc6d2e7dd47447f8de9726ee";

export default node;
