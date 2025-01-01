/**
 * @generated SignedSource<<2f6078b90b8810710d0e1ba060ff3166>>
 * @relayHash 9197840d7deac520b03a5438051de7ff
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9197840d7deac520b03a5438051de7ff

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionRefetchableFragmentQuery$variables = {
  customised_notifications_enabled: boolean;
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
    "name": "customised_notifications_enabled"
  },
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
            "args": [
              {
                "kind": "Variable",
                "name": "customised_notifications_enabled",
                "variableName": "customised_notifications_enabled"
              }
            ],
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
                "condition": "customised_notifications_enabled",
                "kind": "Condition",
                "passingValue": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCustomSubscriptionEvents",
                    "storageKey": null
                  }
                ]
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
    "id": "9197840d7deac520b03a5438051de7ff",
    "metadata": {},
    "name": "SubscriptionSectionRefetchableFragmentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "c933a40c67653bbfe39e05229374b85d";

export default node;
