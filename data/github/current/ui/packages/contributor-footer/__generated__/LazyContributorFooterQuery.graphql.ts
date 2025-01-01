/**
 * @generated SignedSource<<0f0e93e072ab3adfd7081d2e8f622936>>
 * @relayHash f3d0f5ea4e4a9ae8cb400dd970affb0f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f3d0f5ea4e4a9ae8cb400dd970affb0f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LazyContributorFooterQuery$variables = Record<PropertyKey, never>;
export type LazyContributorFooterQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"LazyContributorFooter">;
  } | null | undefined;
};
export type LazyContributorFooterQuery = {
  response: LazyContributorFooterQuery$data;
  variables: LazyContributorFooterQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "abc"
  }
],
v1 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "LazyContributorFooterQuery",
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
                "args": null,
                "kind": "FragmentSpread",
                "name": "LazyContributorFooter"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"abc\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "LazyContributorFooterQuery",
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
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "codeOfConductFileUrl",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "securityPolicyUrl",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "contributingFileUrl",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "supportFileUrl",
                "storageKey": null
              }
            ],
            "type": "Repository",
            "abstractKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": "node(id:\"abc\")"
      }
    ]
  },
  "params": {
    "id": "f3d0f5ea4e4a9ae8cb400dd970affb0f",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        },
        "node.codeOfConductFileUrl": (v1/*: any*/),
        "node.contributingFileUrl": (v1/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.securityPolicyUrl": (v1/*: any*/),
        "node.supportFileUrl": (v1/*: any*/)
      }
    },
    "name": "LazyContributorFooterQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e441e1f1b3c2a1b7bed41851f32d5364";

export default node;
