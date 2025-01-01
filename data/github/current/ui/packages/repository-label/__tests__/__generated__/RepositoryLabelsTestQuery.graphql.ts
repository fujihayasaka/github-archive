/**
 * @generated SignedSource<<1ed55351b9db1eb16d0cfd1354be6c82>>
 * @relayHash 9d38bcd2db65510e3d7804e5c102e937
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9d38bcd2db65510e3d7804e5c102e937

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryLabelsTestQuery$variables = Record<PropertyKey, never>;
export type RepositoryLabelsTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryLabelsInternal">;
  } | null | undefined;
};
export type RepositoryLabelsTestQuery = {
  response: RepositoryLabelsTestQuery$data;
  variables: RepositoryLabelsTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "mockRepositoryId"
  }
],
v1 = {
  "kind": "Literal",
  "name": "first",
  "value": 30
},
v2 = {
  "kind": "Literal",
  "name": "skip",
  "value": 0
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = [
  (v1/*: any*/),
  {
    "fields": [
      {
        "kind": "Literal",
        "name": "direction",
        "value": "ASC"
      },
      {
        "kind": "Literal",
        "name": "field",
        "value": "NAME"
      }
    ],
    "kind": "ObjectValue",
    "name": "orderBy"
  },
  (v2/*: any*/)
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
},
v9 = {
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
    "name": "RepositoryLabelsTestQuery",
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
                  (v2/*: any*/)
                ],
                "kind": "FragmentSpread",
                "name": "RepositoryLabelsInternal"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"mockRepositoryId\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "RepositoryLabelsTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v3/*: any*/),
          (v4/*: any*/),
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
                "args": (v5/*: any*/),
                "concreteType": "LabelConnection",
                "kind": "LinkedField",
                "name": "labels",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "LabelEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Label",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v4/*: any*/),
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
                            "name": "nameHTML",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "color",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "description",
                            "storageKey": null
                          },
                          (v3/*: any*/)
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
                    "kind": "ScalarField",
                    "name": "totalCount",
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
                "storageKey": "labels(first:30,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"},skip:0)"
              },
              {
                "alias": null,
                "args": (v5/*: any*/),
                "filters": [
                  "query",
                  "orderBy",
                  "skip"
                ],
                "handle": "connection",
                "key": "LabelList_labels",
                "kind": "LinkedHandle",
                "name": "labels"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isWritable",
                "storageKey": null
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
        "storageKey": "node(id:\"mockRepositoryId\")"
      }
    ]
  },
  "params": {
    "id": "9d38bcd2db65510e3d7804e5c102e937",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v6/*: any*/),
        "node.id": (v7/*: any*/),
        "node.isWritable": (v8/*: any*/),
        "node.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "node.labels.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LabelEdge"
        },
        "node.labels.edges.cursor": (v6/*: any*/),
        "node.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "node.labels.edges.node.__typename": (v6/*: any*/),
        "node.labels.edges.node.color": (v6/*: any*/),
        "node.labels.edges.node.description": (v9/*: any*/),
        "node.labels.edges.node.id": (v7/*: any*/),
        "node.labels.edges.node.name": (v6/*: any*/),
        "node.labels.edges.node.nameHTML": (v6/*: any*/),
        "node.labels.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "node.labels.pageInfo.endCursor": (v9/*: any*/),
        "node.labels.pageInfo.hasNextPage": (v8/*: any*/),
        "node.labels.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.nameWithOwner": (v6/*: any*/),
        "node.viewerCanPush": (v8/*: any*/)
      }
    },
    "name": "RepositoryLabelsTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b6fe1f2b8a5ecd4b1dd266a27ca39872";

export default node;
