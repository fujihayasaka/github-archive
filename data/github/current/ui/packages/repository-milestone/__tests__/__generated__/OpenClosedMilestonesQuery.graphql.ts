/**
 * @generated SignedSource<<082e2b99ecfa1c503d47e53be979604a>>
 * @relayHash 92e17aafa16e3492996234805e8d2a11
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 92e17aafa16e3492996234805e8d2a11

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OpenClosedMilestonesQuery$variables = Record<PropertyKey, never>;
export type OpenClosedMilestonesQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestones">;
  } | null | undefined;
};
export type OpenClosedMilestonesQuery = {
  response: OpenClosedMilestonesQuery$data;
  variables: OpenClosedMilestonesQuery$variables;
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
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v2 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
],
v3 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "MilestoneConnection"
},
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "OpenClosedMilestonesQuery",
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
                "name": "OpenClosedMilestones"
              }
            ],
            "type": "Repository",
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
    "name": "OpenClosedMilestonesQuery",
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
                "alias": "open",
                "args": [
                  (v1/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "states",
                    "value": "OPEN"
                  }
                ],
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": (v2/*: any*/),
                "storageKey": "milestones(first:0,states:\"OPEN\")"
              },
              {
                "alias": "closed",
                "args": [
                  (v1/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "states",
                    "value": "CLOSED"
                  }
                ],
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": (v2/*: any*/),
                "storageKey": "milestones(first:0,states:\"CLOSED\")"
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
        "storageKey": "node(id:\"123\")"
      }
    ]
  },
  "params": {
    "id": "92e17aafa16e3492996234805e8d2a11",
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
        "node.closed": (v3/*: any*/),
        "node.closed.totalCount": (v4/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.open": (v3/*: any*/),
        "node.open.totalCount": (v4/*: any*/)
      }
    },
    "name": "OpenClosedMilestonesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "f8b76b4bf18ad5b1f03c052982f9baa7";

export default node;
