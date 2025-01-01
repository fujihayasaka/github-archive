/**
 * @generated SignedSource<<39dbb9b17297ac1edf95f1c8644b460c>>
 * @relayHash 53a64700264c88ba5196e54f5a3e2ffd
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 53a64700264c88ba5196e54f5a3e2ffd

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionRefetchableFragmentQuery$variables = {
  id: string;
};
export type SubscriptionSectionRefetchableFragmentQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"SubscriptionSectionRefetchableFragment">;
  } | null | undefined;
};
export type SubscriptionSectionRefetchableFragmentQuery = {
  response: SubscriptionSectionRefetchableFragmentQuery$data;
  variables: SubscriptionSectionRefetchableFragmentQuery$variables;
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
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "SubscriptionSectionRefetchableFragmentQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "SubscriptionSectionRefetchableFragment"
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
    "name": "SubscriptionSectionRefetchableFragmentQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
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
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerThreadSubscriptionFormAction",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCustomSubscriptionEvents",
                "storageKey": null
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
    "id": "53a64700264c88ba5196e54f5a3e2ffd",
    "metadata": {},
    "name": "SubscriptionSectionRefetchableFragmentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a8282d39d09432e901a117d06a51d732";

export default node;
