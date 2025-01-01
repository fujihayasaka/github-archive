/**
 * @generated SignedSource<<5fdec22d5f7127c290dd481cd4b847eb>>
 * @relayHash 7d5f7ac13ff9d53e475f834c63eda91c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7d5f7ac13ff9d53e475f834c63eda91c

import type { ConcreteRequest } from 'relay-runtime';
export type ReprioritizeMilestoneIssueInput = {
  clientMutationId?: string | null | undefined;
  id: string;
  milestoneId: string;
  prevId?: string | null | undefined;
  timestamp: string;
};
export type reprioritizeMilestoneIssueMutation$variables = {
  input: ReprioritizeMilestoneIssueInput;
};
export type reprioritizeMilestoneIssueMutation$data = {
  readonly reprioritizeMilestoneIssue: {
    readonly milestone: {
      readonly id: string;
      readonly updatedAt: string;
    } | null | undefined;
  } | null | undefined;
};
export type reprioritizeMilestoneIssueMutation$rawResponse = {
  readonly reprioritizeMilestoneIssue: {
    readonly milestone: {
      readonly id: string;
      readonly updatedAt: string;
    } | null | undefined;
  } | null | undefined;
};
export type reprioritizeMilestoneIssueMutation = {
  rawResponse: reprioritizeMilestoneIssueMutation$rawResponse;
  response: reprioritizeMilestoneIssueMutation$data;
  variables: reprioritizeMilestoneIssueMutation$variables;
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
    "concreteType": "ReprioritizeMilestoneIssuePayload",
    "kind": "LinkedField",
    "name": "reprioritizeMilestoneIssue",
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
            "name": "updatedAt",
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
    "name": "reprioritizeMilestoneIssueMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "reprioritizeMilestoneIssueMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "7d5f7ac13ff9d53e475f834c63eda91c",
    "metadata": {},
    "name": "reprioritizeMilestoneIssueMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "30aff72adf0f613394b97d1727b41dd0";

export default node;
