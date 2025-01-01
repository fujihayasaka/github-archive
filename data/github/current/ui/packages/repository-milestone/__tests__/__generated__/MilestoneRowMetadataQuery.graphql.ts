/**
 * @generated SignedSource<<ac26c2658527e08357d836f08bb3b7a3>>
 * @relayHash 9ed8b3681b28f333d098994939b52cdc
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9ed8b3681b28f333d098994939b52cdc

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRowMetadataQuery$variables = Record<PropertyKey, never>;
export type MilestoneRowMetadataQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneRowMetadata">;
  } | null | undefined;
};
export type MilestoneRowMetadataQuery = {
  response: MilestoneRowMetadataQuery$data;
  variables: MilestoneRowMetadataQuery$variables;
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
    "name": "MilestoneRowMetadataQuery",
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
                "name": "MilestoneRowMetadata"
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
    "name": "MilestoneRowMetadataQuery",
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
                "name": "title",
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
    "id": "9ed8b3681b28f333d098994939b52cdc",
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
    "name": "MilestoneRowMetadataQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "487359bde2a331f5892d2635939be74b";

export default node;
