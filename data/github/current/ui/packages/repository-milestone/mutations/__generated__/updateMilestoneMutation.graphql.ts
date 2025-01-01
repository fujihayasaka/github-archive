/**
 * @generated SignedSource<<b9725eb4ca50ae7494b6f589815ab5a5>>
 * @relayHash 1d5567fef295bc7769be0ec14110d3aa
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 1d5567fef295bc7769be0ec14110d3aa

import type { ConcreteRequest } from 'relay-runtime';
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
export type UpdateMilestoneInput = {
  clientMutationId?: string | null | undefined;
  description?: string | null | undefined;
  dueOn?: string | null | undefined;
  id: string;
  state?: MilestoneState | null | undefined;
  title?: string | null | undefined;
};
export type updateMilestoneMutation$variables = {
  input: UpdateMilestoneInput;
};
export type updateMilestoneMutation$data = {
  readonly updateMilestone: {
    readonly milestone: {
      readonly closed: boolean;
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type updateMilestoneMutation$rawResponse = {
  readonly updateMilestone: {
    readonly milestone: {
      readonly closed: boolean;
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type updateMilestoneMutation = {
  rawResponse: updateMilestoneMutation$rawResponse;
  response: updateMilestoneMutation$data;
  variables: updateMilestoneMutation$variables;
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
    "alias": null,
    "args": [
      {
        "kind": "Variable",
        "name": "input",
        "variableName": "input"
      }
    ],
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
            "name": "id",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "closed",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "updateMilestoneMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateMilestoneMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "1d5567fef295bc7769be0ec14110d3aa",
    "metadata": {},
    "name": "updateMilestoneMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "7de82b3f406a20a1bcff83a3b90caa3f";

export default node;
