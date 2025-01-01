/**
 * @generated SignedSource<<84d027b4e7e076292856cc2d443b73a2>>
 * @relayHash 52535aabb06ed2be85721b28cdf4ddf3
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 52535aabb06ed2be85721b28cdf4ddf3

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabelOrderField = "CREATED_AT" | "ISSUE_COUNT" | "NAME" | "%future added value";
export type OrderDirection = "ASC" | "DESC" | "%future added value";
export type LabelListQuery$variables = {
  cursor?: string | null | undefined;
  first: number;
  id: string;
  orderDirection?: OrderDirection | null | undefined;
  orderField?: LabelOrderField | null | undefined;
  query?: string | null | undefined;
  skip: number;
};
export type LabelListQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"LabelList">;
  } | null | undefined;
};
export type LabelListQuery = {
  response: LabelListQuery$data;
  variables: LabelListQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "cursor"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v3 = {
  "defaultValue": "DESC",
  "kind": "LocalArgument",
  "name": "orderDirection"
},
v4 = {
  "defaultValue": "NAME",
  "kind": "LocalArgument",
  "name": "orderField"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "query"
},
v6 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "skip"
},
v7 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v8 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v9 = {
  "kind": "Variable",
  "name": "query",
  "variableName": "query"
},
v10 = {
  "kind": "Variable",
  "name": "skip",
  "variableName": "skip"
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v13 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "cursor"
  },
  (v8/*: any*/),
  {
    "fields": [
      {
        "kind": "Variable",
        "name": "direction",
        "variableName": "orderDirection"
      },
      {
        "kind": "Variable",
        "name": "field",
        "variableName": "orderField"
      }
    ],
    "kind": "ObjectValue",
    "name": "orderBy"
  },
  (v9/*: any*/),
  (v10/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "LabelListQuery",
    "selections": [
      {
        "alias": null,
        "args": (v7/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "cursor",
                "variableName": "cursor"
              },
              (v8/*: any*/),
              {
                "kind": "Variable",
                "name": "orderDirection",
                "variableName": "orderDirection"
              },
              {
                "kind": "Variable",
                "name": "orderField",
                "variableName": "orderField"
              },
              (v9/*: any*/),
              (v10/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "LabelList"
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
      (v0/*: any*/),
      (v1/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Operation",
    "name": "LabelListQuery",
    "selections": [
      {
        "alias": null,
        "args": (v7/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v11/*: any*/),
          (v12/*: any*/),
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
                "args": (v13/*: any*/),
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
                          (v12/*: any*/),
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
                          (v11/*: any*/)
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
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v13/*: any*/),
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
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "52535aabb06ed2be85721b28cdf4ddf3",
    "metadata": {},
    "name": "LabelListQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "877381f6a4d0225be11b63a26d9ca9c5";

export default node;
