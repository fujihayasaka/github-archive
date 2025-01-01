/**
 * @generated SignedSource<<3cdfa8ac1d3f9234a8dd9a8d8e2cc710>>
 * @relayHash d5ce267f88b8441638bc9b8da30ea8f0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d5ce267f88b8441638bc9b8da30ea8f0

import { ConcreteRequest } from 'relay-runtime';
export type IssueClosedStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "%future added value";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type updateIssueStateMutationCloseMutation$variables = {
  duplicateIssueId?: string | null | undefined;
  id: string;
  newStateReason: IssueClosedStateReason;
};
export type updateIssueStateMutationCloseMutation$data = {
  readonly closeIssue: {
    readonly issue: {
      readonly duplicateOf: {
        readonly number: number;
        readonly url: string;
      } | null | undefined;
      readonly id: string;
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueStateMutationCloseMutation$rawResponse = {
  readonly closeIssue: {
    readonly issue: {
      readonly duplicateOf: {
        readonly id: string;
        readonly number: number;
        readonly url: string;
      } | null | undefined;
      readonly id: string;
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueStateMutationCloseMutation = {
  rawResponse: updateIssueStateMutationCloseMutation$rawResponse;
  response: updateIssueStateMutationCloseMutation$data;
  variables: updateIssueStateMutationCloseMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "duplicateIssueId"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "newStateReason"
},
v3 = [
  {
    "fields": [
      {
        "kind": "Variable",
        "name": "duplicateIssueId",
        "variableName": "duplicateIssueId"
      },
      {
        "kind": "Variable",
        "name": "issueId",
        "variableName": "id"
      },
      {
        "kind": "Variable",
        "name": "stateReason",
        "variableName": "newStateReason"
      }
    ],
    "kind": "ObjectValue",
    "name": "input"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "enableDuplicate",
      "value": true
    }
  ],
  "kind": "ScalarField",
  "name": "stateReason",
  "storageKey": "stateReason(enableDuplicate:true)"
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "updateIssueStateMutationCloseMutation",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "CloseIssuePayload",
        "kind": "LinkedField",
        "name": "closeIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v4/*: any*/),
              (v5/*: any*/),
              (v6/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v7/*: any*/),
                  (v8/*: any*/)
                ],
                "storageKey": null
              }
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
    "argumentDefinitions": [
      (v1/*: any*/),
      (v2/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "updateIssueStateMutationCloseMutation",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "CloseIssuePayload",
        "kind": "LinkedField",
        "name": "closeIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v4/*: any*/),
              (v5/*: any*/),
              (v6/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v7/*: any*/),
                  (v8/*: any*/),
                  (v4/*: any*/)
                ],
                "storageKey": null
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
    "id": "d5ce267f88b8441638bc9b8da30ea8f0",
    "metadata": {},
    "name": "updateIssueStateMutationCloseMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "ade599884df0a1457507638db04e2c97";

export default node;
