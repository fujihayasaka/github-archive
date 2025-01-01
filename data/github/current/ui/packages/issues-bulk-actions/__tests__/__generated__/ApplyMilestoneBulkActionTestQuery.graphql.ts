/**
 * @generated SignedSource<<8ee6a9bc6980c7d4523e64a3eb690223>>
 * @relayHash 0137ab38231ca97a7ea9197745419fea
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 0137ab38231ca97a7ea9197745419fea

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ApplyMilestoneBulkActionTestQuery$variables = {
  ids: ReadonlyArray<string>;
};
export type ApplyMilestoneBulkActionTestQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly id?: string;
    readonly milestone?: {
      readonly " $fragmentSpreads": FragmentRefs<"MilestonePickerMilestone">;
    } | null | undefined;
  } | null | undefined>;
};
export type ApplyMilestoneBulkActionTestQuery = {
  response: ApplyMilestoneBulkActionTestQuery$data;
  variables: ApplyMilestoneBulkActionTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "ids"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "ids"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = [
  (v2/*: any*/),
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
    "name": "closed",
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
    "name": "progressPercentage",
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
    "name": "closedAt",
    "storageKey": null
  }
],
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v6 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ApplyMilestoneBulkActionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": [
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "MilestonePickerMilestone",
                    "selections": (v3/*: any*/),
                    "args": null,
                    "argumentDefinitions": []
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "Issue",
            "abstractKey": null
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
    "name": "ApplyMilestoneBulkActionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
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
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": (v3/*: any*/),
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
    "id": "0137ab38231ca97a7ea9197745419fea",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "nodes": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "Node"
        },
        "nodes.__typename": (v4/*: any*/),
        "nodes.id": (v5/*: any*/),
        "nodes.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "nodes.milestone.closed": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "nodes.milestone.closedAt": (v6/*: any*/),
        "nodes.milestone.dueOn": (v6/*: any*/),
        "nodes.milestone.id": (v5/*: any*/),
        "nodes.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "nodes.milestone.title": (v4/*: any*/),
        "nodes.milestone.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "ApplyMilestoneBulkActionTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "30632e36743ed1cead88a4a768a95441";

export default node;
