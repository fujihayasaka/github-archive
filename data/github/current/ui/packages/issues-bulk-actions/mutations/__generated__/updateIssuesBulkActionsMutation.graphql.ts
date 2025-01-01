/**
 * @generated SignedSource<<64d8a560697cb4a283cdacef26573c5c>>
 * @relayHash dfb2a4b140aa897b294cc6d1a17dbeae
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID dfb2a4b140aa897b294cc6d1a17dbeae

import type { ConcreteRequest } from 'relay-runtime';
export type IssueClosedStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "%future added value";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type UpdateIssuesBulkInput = {
  addToProjectV2Ids?: ReadonlyArray<string> | null | undefined;
  applyAssigneeIds?: ReadonlyArray<string> | null | undefined;
  applyLabelIds?: ReadonlyArray<string> | null | undefined;
  clearMilestone?: boolean | null | undefined;
  clientMutationId?: string | null | undefined;
  ids: ReadonlyArray<string>;
  issueTypeId?: string | null | undefined;
  milestoneId?: string | null | undefined;
  removeAssigneeIds?: ReadonlyArray<string> | null | undefined;
  removeFromProjectV2Ids?: ReadonlyArray<string> | null | undefined;
  removeLabelIds?: ReadonlyArray<string> | null | undefined;
  state?: IssueState | null | undefined;
  stateReason?: IssueClosedStateReason | null | undefined;
  unsetIssueType?: boolean | null | undefined;
};
export type updateIssuesBulkActionsMutation$variables = {
  input: UpdateIssuesBulkInput;
};
export type updateIssuesBulkActionsMutation$data = {
  readonly updateIssuesBulk: {
    readonly jobId: string | null | undefined;
  } | null | undefined;
};
export type updateIssuesBulkActionsMutation$rawResponse = {
  readonly updateIssuesBulk: {
    readonly jobId: string | null | undefined;
  } | null | undefined;
};
export type updateIssuesBulkActionsMutation = {
  rawResponse: updateIssuesBulkActionsMutation$rawResponse;
  response: updateIssuesBulkActionsMutation$data;
  variables: updateIssuesBulkActionsMutation$variables;
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
    "concreteType": "UpdateIssuesBulkPayload",
    "kind": "LinkedField",
    "name": "updateIssuesBulk",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "jobId",
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
    "name": "updateIssuesBulkActionsMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateIssuesBulkActionsMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "dfb2a4b140aa897b294cc6d1a17dbeae",
    "metadata": {},
    "name": "updateIssuesBulkActionsMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "2187d2996ee91c8c84510d55982245d5";

export default node;
