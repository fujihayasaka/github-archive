/**
 * @generated SignedSource<<464fd07f4a8589924dd832412e065f45>>
 * @relayHash b9a4afc78884025457f655e918413b6a
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b9a4afc78884025457f655e918413b6a

import { ConcreteRequest } from 'relay-runtime';
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
export type updateIssueLabelsBulkByQueryMutation$variables = {
  input: UpdateIssuesBulkByQueryInput;
};
export type updateIssueLabelsBulkByQueryMutation$data = {
  readonly updateIssuesBulkByQuery: {
    readonly jobId: string | null | undefined;
  } | null | undefined;
};
export type updateIssueLabelsBulkByQueryMutation$rawResponse = {
  readonly updateIssuesBulkByQuery: {
    readonly jobId: string | null | undefined;
  } | null | undefined;
};
export type updateIssueLabelsBulkByQueryMutation = {
  rawResponse: updateIssueLabelsBulkByQueryMutation$rawResponse;
  response: updateIssueLabelsBulkByQueryMutation$data;
  variables: updateIssueLabelsBulkByQueryMutation$variables;
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
    "name": "updateIssueLabelsBulkByQueryMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateIssueLabelsBulkByQueryMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "b9a4afc78884025457f655e918413b6a",
    "metadata": {},
    "name": "updateIssueLabelsBulkByQueryMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "bc300fe790ca50bd21facb091f332359";

export default node;
