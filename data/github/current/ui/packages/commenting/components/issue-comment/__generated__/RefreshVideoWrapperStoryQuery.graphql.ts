/**
 * @generated SignedSource<<dfd3fcd62af5f1591667f903ac99e1df>>
 * @relayHash b7acdf9fd145f675f9a9943ab7722272
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b7acdf9fd145f675f9a9943ab7722272

import type { ConcreteRequest } from 'relay-runtime';
export type RefreshVideoWrapperStoryQuery$variables = Record<PropertyKey, never>;
export type RefreshVideoWrapperStoryQuery$data = {
  readonly node: {
    readonly id: string;
  } | null | undefined;
};
export type RefreshVideoWrapperStoryQuery = {
  response: RefreshVideoWrapperStoryQuery$data;
  variables: RefreshVideoWrapperStoryQuery$variables;
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
  "name": "id",
  "storageKey": null
},
v2 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "RefreshVideoWrapperStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/)
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
    "name": "RefreshVideoWrapperStoryQuery",
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
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          {
            "kind": "TypeDiscriminator",
            "abstractKey": "__isNode"
          },
          (v1/*: any*/)
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ]
  },
  "params": {
    "id": "b7acdf9fd145f675f9a9943ab7722272",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isNode": (v2/*: any*/),
        "node.__typename": (v2/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        }
      }
    },
    "name": "RefreshVideoWrapperStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "13e9558e326fbbeb134cdf1b55305eab";

export default node;
