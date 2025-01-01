/**
 * @generated SignedSource<<49a804d7c807e589bafa6e8ca84291eb>>
 * @relayHash a9ae2354e6380942865b0f74b338212f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a9ae2354e6380942865b0f74b338212f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestonePickerQuery$variables = {
  owner: string;
  repo: string;
};
export type MilestonePickerQuery$data = {
  readonly repository: {
    readonly viewerIssueCreationPermissions: {
      readonly milestoneable: boolean;
    };
    readonly " $fragmentSpreads": FragmentRefs<"MilestonePickerRecentlyUpdatedMilestones">;
  } | null | undefined;
};
export type MilestonePickerQuery = {
  response: MilestonePickerQuery$data;
  variables: MilestonePickerQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "owner"
  },
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "repo"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueCreationPermissions",
  "kind": "LinkedField",
  "name": "viewerIssueCreationPermissions",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "milestoneable",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "MilestonePickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "MilestonePickerRecentlyUpdatedMilestones"
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
    "name": "MilestonePickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "alias": null,
            "args": [
              {
                "kind": "Literal",
                "name": "first",
                "value": 100
              },
              {
                "kind": "Literal",
                "name": "orderBy",
                "value": {
                  "direction": "DESC",
                  "field": "UPDATED_AT"
                }
              },
              {
                "kind": "Literal",
                "name": "orderByStates",
                "value": [
                  "OPEN",
                  "CLOSED"
                ]
              }
            ],
            "concreteType": "MilestoneConnection",
            "kind": "LinkedField",
            "name": "milestones",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": [
                  (v3/*: any*/),
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
                "storageKey": null
              }
            ],
            "storageKey": "milestones(first:100,orderBy:{\"direction\":\"DESC\",\"field\":\"UPDATED_AT\"},orderByStates:[\"OPEN\",\"CLOSED\"])"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "a9ae2354e6380942865b0f74b338212f",
    "metadata": {},
    "name": "MilestonePickerQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "98ef633283cc4d1c1aee9ad37fefaf7a";

export default node;
