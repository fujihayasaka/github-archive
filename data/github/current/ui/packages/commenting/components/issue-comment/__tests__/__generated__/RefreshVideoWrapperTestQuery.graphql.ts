/**
 * @generated SignedSource<<92c68cada65cd0773227151550bd3dad>>
 * @relayHash 21e7f7b37a79196226be3e9ef3281c23
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 21e7f7b37a79196226be3e9ef3281c23

import type { ConcreteRequest } from 'relay-runtime';
export type RefreshVideoWrapperTestQuery$variables = Record<PropertyKey, never>;
export type RefreshVideoWrapperTestQuery$data = {
  readonly node: {
    readonly id: string;
  } | null | undefined;
};
export type RefreshVideoWrapperTestQuery = {
  response: RefreshVideoWrapperTestQuery$data;
  variables: RefreshVideoWrapperTestQuery$variables;
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
    "name": "RefreshVideoWrapperTestQuery",
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
    "name": "RefreshVideoWrapperTestQuery",
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
    "id": "21e7f7b37a79196226be3e9ef3281c23",
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
    "name": "RefreshVideoWrapperTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "10c5bf7f41a3856ee9191f46018182d3";

export default node;
