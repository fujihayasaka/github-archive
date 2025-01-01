/**
 * @generated SignedSource<<506d9d96ca7d456b60059cf804ec14f5>>
 * @relayHash e3df09be4e30c35e0655379516166fe5
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID e3df09be4e30c35e0655379516166fe5

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ApplyLabelsBulkActionTestQuery$variables = {
  ids: ReadonlyArray<string>;
};
export type ApplyLabelsBulkActionTestQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly id?: string;
    readonly labels?: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
      } | null | undefined> | null | undefined;
    } | null | undefined;
  } | null | undefined>;
};
export type ApplyLabelsBulkActionTestQuery = {
  response: ApplyLabelsBulkActionTestQuery$data;
  variables: ApplyLabelsBulkActionTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "ids"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "ids"
  }
],
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
    "value": 20
  },
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
v4 = [
  (v2/*: any*/),
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
    "name": "description",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "url",
    "storageKey": null
  }
],
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ApplyLabelsBulkActionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "LabelConnection",
                "kind": "LinkedField",
                "name": "labels",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Label",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "LabelPickerLabel",
                        "selections": (v4/*: any*/),
                        "args": null,
                        "argumentDefinitions": []
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
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
    "name": "ApplyLabelsBulkActionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "LabelConnection",
                "kind": "LinkedField",
                "name": "labels",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Label",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": (v4/*: any*/),
                    "storageKey": null
                  }
                ],
                "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
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
    "id": "e3df09be4e30c35e0655379516166fe5",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "nodes": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "Node"
        },
        "nodes.__typename": (v5/*: any*/),
        "nodes.id": (v6/*: any*/),
        "nodes.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "nodes.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "nodes.labels.nodes.color": (v5/*: any*/),
        "nodes.labels.nodes.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "nodes.labels.nodes.id": (v6/*: any*/),
        "nodes.labels.nodes.name": (v5/*: any*/),
        "nodes.labels.nodes.nameHTML": (v5/*: any*/),
        "nodes.labels.nodes.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "ApplyLabelsBulkActionTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "9da327e49b9a4ed9a49a6f0334f47cbc";

export default node;
