/**
 * @generated SignedSource<<ae82e1765a5cf7f1e6ffad548f85e482>>
 * @relayHash 888ca5c7c51f5059d3d646b420493e98
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 888ca5c7c51f5059d3d646b420493e98

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRowMenuTestQuery$variables = Record<PropertyKey, never>;
export type MilestoneRowMenuTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneRowMenu">;
  } | null | undefined;
};
export type MilestoneRowMenuTestQuery = {
  response: MilestoneRowMenuTestQuery$data;
  variables: MilestoneRowMenuTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "M_123"
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
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "MilestoneRowMenuTestQuery",
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
                "name": "MilestoneRowMenu"
              }
            ],
            "type": "Milestone",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"M_123\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "MilestoneRowMenuTestQuery",
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
                "name": "state",
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
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v1/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "type": "Milestone",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"M_123\")"
      }
    ]
  },
  "params": {
    "id": "888ca5c7c51f5059d3d646b420493e98",
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
        "node.id": (v2/*: any*/),
        "node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.repository.id": (v2/*: any*/),
        "node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "MilestoneState"
        },
        "node.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "MilestoneRowMenuTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "4031cdbccc0779b6dbb12f4e1b8c6b37";

export default node;
