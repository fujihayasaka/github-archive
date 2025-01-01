/**
 * @generated SignedSource<<fcc4858edf3b3ee329c26e73760ce5e2>>
 * @relayHash 518920fcb374fb2c22831ce13ceace8b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 518920fcb374fb2c22831ce13ceace8b

import type { ConcreteRequest } from 'relay-runtime';
export type CreateMilestoneInput = {
  clientMutationId?: string | null | undefined;
  description?: string | null | undefined;
  dueOn?: string | null | undefined;
  repositoryId: string;
  title: string;
};
export type createMilestoneMutation$variables = {
  input: CreateMilestoneInput;
};
export type createMilestoneMutation$data = {
  readonly createMilestone: {
    readonly milestone: {
      readonly closed: boolean;
      readonly closedAt: string | null | undefined;
      readonly dueOn: string | null | undefined;
      readonly id: string;
      readonly progressPercentage: number;
      readonly title: string;
      readonly url: string;
    } | null | undefined;
  } | null | undefined;
};
export type createMilestoneMutation$rawResponse = {
  readonly createMilestone: {
    readonly milestone: {
      readonly closed: boolean;
      readonly closedAt: string | null | undefined;
      readonly dueOn: string | null | undefined;
      readonly id: string;
      readonly progressPercentage: number;
      readonly title: string;
      readonly url: string;
    } | null | undefined;
  } | null | undefined;
};
export type createMilestoneMutation = {
  rawResponse: createMilestoneMutation$rawResponse;
  response: createMilestoneMutation$data;
  variables: createMilestoneMutation$variables;
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
    "concreteType": "CreateMilestonePayload",
    "kind": "LinkedField",
    "name": "createMilestone",
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
            "name": "closedAt",
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
            "name": "title",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "url",
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
    "name": "createMilestoneMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "createMilestoneMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "518920fcb374fb2c22831ce13ceace8b",
    "metadata": {},
    "name": "createMilestoneMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "04f6d08fc81ee446c151c8e3f0043366";

export default node;
