/**
 * @generated SignedSource<<4721faa03160df40d6a5c136505c48df>>
 * @relayHash a1404ba230fd4248febc2adc9eea7281
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a1404ba230fd4248febc2adc9eea7281

import type { ConcreteRequest } from 'relay-runtime';
export type DeleteIssueInput = {
  clientMutationId?: string | null | undefined;
  issueId: string;
};
export type deleteIssueMutation$variables = {
  input: DeleteIssueInput;
};
export type deleteIssueMutation$data = {
  readonly deleteIssue: {
    readonly issue: {
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type deleteIssueMutation$rawResponse = {
  readonly deleteIssue: {
    readonly issue: {
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type deleteIssueMutation = {
  rawResponse: deleteIssueMutation$rawResponse;
  response: deleteIssueMutation$data;
  variables: deleteIssueMutation$variables;
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
    "concreteType": "DeleteIssuePayload",
    "kind": "LinkedField",
    "name": "deleteIssue",
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
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
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
    "name": "deleteIssueMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "deleteIssueMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "a1404ba230fd4248febc2adc9eea7281",
    "metadata": {},
    "name": "deleteIssueMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "03043bd9975becdb0e86cee81f237bb7";

export default node;
