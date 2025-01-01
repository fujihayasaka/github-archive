/**
 * @generated SignedSource<<8ba9856c2b60c6c268a945adefbacac3>>
 * @relayHash 3bbed252fba522eb614bc7d07f407808
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3bbed252fba522eb614bc7d07f407808

import type { ConcreteRequest } from 'relay-runtime';
export type CreateMilestoneInput = {
  clientMutationId?: string | null | undefined;
  description?: string | null | undefined;
  dueOn?: string | null | undefined;
  repositoryId: string;
  title: string;
};
export type createRepositoryMilestoneMutation$variables = {
  input: CreateMilestoneInput;
};
export type createRepositoryMilestoneMutation$data = {
  readonly createMilestone: {
    readonly errors: ReadonlyArray<{
      readonly message: string;
    }>;
    readonly milestone: {
      readonly number: number;
    } | null | undefined;
  } | null | undefined;
};
export type createRepositoryMilestoneMutation = {
  response: createRepositoryMilestoneMutation$data;
  variables: createRepositoryMilestoneMutation$variables;
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
  "name": "number",
  "storageKey": null
},
v3 = {
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
    "name": "createRepositoryMilestoneMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
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
              (v2/*: any*/)
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
              (v3/*: any*/)
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
    "name": "createRepositoryMilestoneMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
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
              (v2/*: any*/),
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
              (v3/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "3bbed252fba522eb614bc7d07f407808",
    "metadata": {},
    "name": "createRepositoryMilestoneMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "0125b820c8c6a0ed165bd9e3da6cf56e";

export default node;
