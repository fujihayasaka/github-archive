/**
 * @generated SignedSource<<a648c3e9c929c8c3894c80d18b133491>>
 * @relayHash 875a2aa4fafaa844903651541bfd85b4
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 875a2aa4fafaa844903651541bfd85b4

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
export type UpdateMilestoneInput = {
  clientMutationId?: string | null | undefined;
  description?: string | null | undefined;
  dueOn?: string | null | undefined;
  id: string;
  state?: MilestoneState | null | undefined;
  title?: string | null | undefined;
};
export type updateMilestoneDetailsMutation$variables = {
  input: UpdateMilestoneInput;
};
export type updateMilestoneDetailsMutation$data = {
  readonly updateMilestone: {
    readonly errors: ReadonlyArray<{
      readonly message: string;
    }>;
    readonly milestone: {
      readonly " $fragmentSpreads": FragmentRefs<"MilestoneDetail">;
    } | null | undefined;
  } | null | undefined;
};
export type updateMilestoneDetailsMutation = {
  response: updateMilestoneDetailsMutation$data;
  variables: updateMilestoneDetailsMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "message",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "updateMilestoneDetailsMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateMilestonePayload",
        "kind": "LinkedField",
        "name": "updateMilestone",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Milestone",
            "kind": "LinkedField",
            "name": "milestone",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MilestoneDetail"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "errors",
            "plural": true,
            "selections": [
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateMilestoneDetailsMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "UpdateMilestonePayload",
        "kind": "LinkedField",
        "name": "updateMilestone",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Milestone",
            "kind": "LinkedField",
            "name": "milestone",
            "plural": false,
            "selections": [
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
                "name": "updatedAt",
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
                "name": "descriptionHTML",
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
                "name": "dueOn",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "id",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "errors",
            "plural": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "__typename",
                "storageKey": null
              },
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "875a2aa4fafaa844903651541bfd85b4",
    "metadata": {},
    "name": "updateMilestoneDetailsMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "64505a94b96eb0c14b201becddec86a0";

export default node;
