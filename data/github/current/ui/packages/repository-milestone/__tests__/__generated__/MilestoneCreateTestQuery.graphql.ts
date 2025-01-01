/**
 * @generated SignedSource<<496b28f4025a10c1d99bad4fb77ba6d6>>
 * @relayHash 4d7b580281ccdaf2a77a449130889bd5
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4d7b580281ccdaf2a77a449130889bd5

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneCreateTestQuery$variables = Record<PropertyKey, never>;
export type MilestoneCreateTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneCreateFormRepositoryQuery">;
  } | null | undefined;
};
export type MilestoneCreateTestQuery = {
  response: MilestoneCreateTestQuery$data;
  variables: MilestoneCreateTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "repo-123"
  }
],
v1 = {
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
    "name": "MilestoneCreateTestQuery",
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
                "name": "MilestoneCreateFormRepositoryQuery"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"repo-123\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "MilestoneCreateTestQuery",
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
                "name": "nameWithOwner",
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
        "storageKey": "node(id:\"repo-123\")"
      }
    ]
  },
  "params": {
    "id": "4d7b580281ccdaf2a77a449130889bd5",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v1/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.nameWithOwner": (v1/*: any*/),
        "node.viewerCanPush": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "MilestoneCreateTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "414dd154d3326d790a84e35c396562ef";

export default node;
