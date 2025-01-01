/**
 * @generated SignedSource<<f45d5d7c38359307d2062620e9c035ef>>
 * @relayHash 35dfbb421568af196e7028fa0d6b61ed
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 35dfbb421568af196e7028fa0d6b61ed

import type { ConcreteRequest } from 'relay-runtime';
export type IssueClosedStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "%future added value";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type UpdateIssuesBulkByQueryInput = {
  addToProjectV2Ids?: ReadonlyArray<string> | null | undefined;
  applyAssigneeIds?: ReadonlyArray<string> | null | undefined;
  applyLabelIds?: ReadonlyArray<string> | null | undefined;
  clearMilestone?: boolean | null | undefined;
  clientMutationId?: string | null | undefined;
  issueTypeId?: string | null | undefined;
  milestoneId?: string | null | undefined;
  query: string;
  removeAssigneeIds?: ReadonlyArray<string> | null | undefined;
  removeFromProjectV2Ids?: ReadonlyArray<string> | null | undefined;
  removeLabelIds?: ReadonlyArray<string> | null | undefined;
  repositoryId: string;
  state?: IssueState | null | undefined;
  stateReason?: IssueClosedStateReason | null | undefined;
  unsetIssueType?: boolean | null | undefined;
};
export type updateIssuesBulkActionsByQueryMutation$variables = {
  input: UpdateIssuesBulkByQueryInput;
};
export type updateIssuesBulkActionsByQueryMutation$data = {
  readonly updateIssuesBulkByQuery: {
    readonly jobId: string | null | undefined;
  } | null | undefined;
};
export type updateIssuesBulkActionsByQueryMutation$rawResponse = {
  readonly updateIssuesBulkByQuery: {
    readonly jobId: string | null | undefined;
  } | null | undefined;
};
export type updateIssuesBulkActionsByQueryMutation = {
  rawResponse: updateIssuesBulkActionsByQueryMutation$rawResponse;
  response: updateIssuesBulkActionsByQueryMutation$data;
  variables: updateIssuesBulkActionsByQueryMutation$variables;
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
    "concreteType": "UpdateIssuesBulkByQueryPayload",
    "kind": "LinkedField",
    "name": "updateIssuesBulkByQuery",
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
    "name": "updateIssuesBulkActionsByQueryMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateIssuesBulkActionsByQueryMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "35dfbb421568af196e7028fa0d6b61ed",
    "metadata": {},
    "name": "updateIssuesBulkActionsByQueryMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "70f1e01b038fd680e1a06c05a1b9138c";

export default node;
