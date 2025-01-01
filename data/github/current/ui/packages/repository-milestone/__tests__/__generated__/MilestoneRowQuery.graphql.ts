/**
 * @generated SignedSource<<8464d3c6fe57a3c52ba0680303bdb84e>>
 * @relayHash 1905070b49baff869f0122f83998c24e
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 1905070b49baff869f0122f83998c24e

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRowQuery$variables = Record<PropertyKey, never>;
export type MilestoneRowQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneRow">;
  } | null | undefined;
};
export type MilestoneRowQuery = {
  response: MilestoneRowQuery$data;
  variables: MilestoneRowQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "123"
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
},
v3 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "MilestoneRowQuery",
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
                "name": "MilestoneRow"
              }
            ],
            "type": "Milestone",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"123\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "MilestoneRowQuery",
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
          (v1/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
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
                "name": "title",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "url",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "state",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v1/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "progressPercentage",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "openIssueCount",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "closedIssueCount",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "dueOn",
                "storageKey": null
              }
            ],
            "type": "Milestone",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"123\")"
      }
    ]
  },
  "params": {
    "id": "1905070b49baff869f0122f83998c24e",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v2/*: any*/),
        "node.closedIssueCount": (v3/*: any*/),
        "node.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "node.dueOn": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "node.id": (v4/*: any*/),
        "node.openIssueCount": (v3/*: any*/),
        "node.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.repository.id": (v4/*: any*/),
        "node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "MilestoneState"
        },
        "node.title": (v2/*: any*/),
        "node.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "MilestoneRowQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "26e9bcf08a828a29a63b1f834765824b";

export default node;
