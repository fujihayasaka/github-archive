/**
 * @generated SignedSource<<755827f78f2534725cbb734f0a1fb606>>
 * @relayHash a18878441a869b0aa0cc371c1b84cdca
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a18878441a869b0aa0cc371c1b84cdca

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabelOrderField = "CREATED_AT" | "ISSUE_COUNT" | "NAME" | "%future added value";
export type OrderDirection = "ASC" | "DESC" | "%future added value";
export type RepositoryLabelIndexPageQuery$variables = {
  first: number;
  name: string;
  orderDirection?: OrderDirection | null | undefined;
  orderField?: LabelOrderField | null | undefined;
  owner: string;
  query?: string | null | undefined;
  skip: number;
};
export type RepositoryLabelIndexPageQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryLabelIndexPageContentInternal">;
  } | null | undefined;
};
export type RepositoryLabelIndexPageQuery = {
  response: RepositoryLabelIndexPageQuery$data;
  variables: RepositoryLabelIndexPageQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
},
v2 = {
  "defaultValue": "ASC",
  "kind": "LocalArgument",
  "name": "orderDirection"
},
v3 = {
  "defaultValue": "NAME",
  "kind": "LocalArgument",
  "name": "orderField"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
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
    "name": "name",
    "variableName": "name"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
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
  "name": "id",
  "storageKey": null
},
v12 = [
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
    "name": "RepositoryLabelIndexPageQuery",
    "selections": [
      {
        "alias": null,
        "args": (v7/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": [
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
            "name": "RepositoryLabelIndexPageContentInternal"
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
      (v4/*: any*/),
      (v0/*: any*/),
      (v3/*: any*/),
      (v2/*: any*/),
      (v6/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Operation",
    "name": "RepositoryLabelIndexPageQuery",
    "selections": [
      {
        "alias": null,
        "args": (v7/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v11/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameWithOwner",
            "storageKey": null
          },
          {
            "alias": null,
            "args": (v12/*: any*/),
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
                      (v11/*: any*/),
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
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "__typename",
                        "storageKey": null
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
            "args": (v12/*: any*/),
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
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "a18878441a869b0aa0cc371c1b84cdca",
    "metadata": {},
    "name": "RepositoryLabelIndexPageQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "edd5cb2905962ab9ba31b6731ba75bec";

export default node;
