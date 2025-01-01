/**
 * @generated SignedSource<<5cd2342cc9ca1eb26315447fd2505b13>>
 * @relayHash 6a0d967e7c0851a17cc7be6b19d438b4
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 6a0d967e7c0851a17cc7be6b19d438b4

import type { ConcreteRequest } from 'relay-runtime';
export type DeleteLabelInput = {
  clientMutationId?: string | null | undefined;
  id: string;
};
export type deleteLabelMutation$variables = {
  input: DeleteLabelInput;
};
export type deleteLabelMutation$data = {
  readonly deleteLabel: {
    readonly clientMutationId: string | null | undefined;
  } | null | undefined;
};
export type deleteLabelMutation$rawResponse = {
  readonly deleteLabel: {
    readonly clientMutationId: string | null | undefined;
  } | null | undefined;
};
export type deleteLabelMutation = {
  rawResponse: deleteLabelMutation$rawResponse;
  response: deleteLabelMutation$data;
  variables: deleteLabelMutation$variables;
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
    "concreteType": "DeleteLabelPayload",
    "kind": "LinkedField",
    "name": "deleteLabel",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "clientMutationId",
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
    "name": "deleteLabelMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "deleteLabelMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "6a0d967e7c0851a17cc7be6b19d438b4",
    "metadata": {},
    "name": "deleteLabelMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "c579787fb72c7a89c766b95d6330f372";

export default node;
