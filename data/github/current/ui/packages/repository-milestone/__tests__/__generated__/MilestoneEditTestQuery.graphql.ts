/**
 * @generated SignedSource<<3f6761ce7a6acc94eb638370b048ed50>>
 * @relayHash cddeee6aeb0489b4be1ef4c5c02687b1
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID cddeee6aeb0489b4be1ef4c5c02687b1

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneEditTestQuery$variables = Record<PropertyKey, never>;
export type MilestoneEditTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneEditFormRepositoryQuery">;
  } | null | undefined;
};
export type MilestoneEditTestQuery = {
  response: MilestoneEditTestQuery$data;
  variables: MilestoneEditTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "repo-123"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 1
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
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
    "name": "MilestoneEditTestQuery",
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
                "args": (v1/*: any*/),
                "kind": "FragmentSpread",
                "name": "MilestoneEditFormRepositoryQuery"
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
    "name": "MilestoneEditTestQuery",
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
          (v2/*: any*/),
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
              },
              {
                "alias": null,
                "args": (v1/*: any*/),
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "number",
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
                    "name": "description",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "dueOn",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "state",
                    "storageKey": null
                  }
                ],
                "storageKey": "milestone(number:1)"
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
    "id": "cddeee6aeb0489b4be1ef4c5c02687b1",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v3/*: any*/),
        "node.id": (v4/*: any*/),
        "node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestone.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "node.milestone.dueOn": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "node.milestone.id": (v4/*: any*/),
        "node.milestone.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.milestone.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "MilestoneState"
        },
        "node.milestone.title": (v3/*: any*/),
        "node.nameWithOwner": (v3/*: any*/),
        "node.viewerCanPush": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "MilestoneEditTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "7b69e5300d70c91fafa34d67a488afdd";

export default node;
