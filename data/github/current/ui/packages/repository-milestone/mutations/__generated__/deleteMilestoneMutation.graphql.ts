/**
 * @generated SignedSource<<470508ee49027c0eb141af21f8a40e1b>>
 * @relayHash 51d866034128db62d668c9e305002192
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 51d866034128db62d668c9e305002192

import type { ConcreteRequest } from 'relay-runtime';
export type DeleteMilestoneInput = {
  clientMutationId?: string | null | undefined;
  id: string;
};
export type deleteMilestoneMutation$variables = {
  input: DeleteMilestoneInput;
};
export type deleteMilestoneMutation$data = {
  readonly deleteMilestone: {
    readonly milestone: {
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type deleteMilestoneMutation$rawResponse = {
  readonly deleteMilestone: {
    readonly milestone: {
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type deleteMilestoneMutation = {
  rawResponse: deleteMilestoneMutation$rawResponse;
  response: deleteMilestoneMutation$data;
  variables: deleteMilestoneMutation$variables;
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
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "deleteMilestoneMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "DeleteMilestonePayload",
        "kind": "LinkedField",
        "name": "deleteMilestone",
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
    "name": "deleteMilestoneMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "DeleteMilestonePayload",
        "kind": "LinkedField",
        "name": "deleteMilestone",
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
              (v2/*: any*/),
              {
                "alias": null,
                "args": null,
                "filters": null,
                "handle": "deleteRecord",
                "key": "",
                "kind": "ScalarHandle",
                "name": "id"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "51d866034128db62d668c9e305002192",
    "metadata": {},
    "name": "deleteMilestoneMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "d96316a2c94a676025441e29c80749db";

export default node;
