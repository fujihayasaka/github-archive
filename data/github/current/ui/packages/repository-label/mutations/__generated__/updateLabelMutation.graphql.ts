/**
 * @generated SignedSource<<e3c74e3dd10bb76fc8457a43413edd3d>>
 * @relayHash 01f658521cc6c78250b2636d2c75f846
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 01f658521cc6c78250b2636d2c75f846

import type { ConcreteRequest } from 'relay-runtime';
export type UpdateLabelInput = {
  clientMutationId?: string | null | undefined;
  color?: string | null | undefined;
  description?: string | null | undefined;
  id: string;
  name?: string | null | undefined;
};
export type updateLabelMutation$variables = {
  input: UpdateLabelInput;
};
export type updateLabelMutation$data = {
  readonly updateLabel: {
    readonly label: {
      readonly color: string;
      readonly description: string | null | undefined;
      readonly id: string;
      readonly name: string;
      readonly nameHTML: string;
    } | null | undefined;
  } | null | undefined;
};
export type updateLabelMutation$rawResponse = {
  readonly updateLabel: {
    readonly label: {
      readonly color: string;
      readonly description: string | null | undefined;
      readonly id: string;
      readonly name: string;
      readonly nameHTML: string;
    } | null | undefined;
  } | null | undefined;
};
export type updateLabelMutation = {
  rawResponse: updateLabelMutation$rawResponse;
  response: updateLabelMutation$data;
  variables: updateLabelMutation$variables;
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
    "concreteType": "UpdateLabelPayload",
    "kind": "LinkedField",
    "name": "updateLabel",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "Label",
        "kind": "LinkedField",
        "name": "label",
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
            "name": "name",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameHTML",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "description",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "color",
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
    "name": "updateLabelMutation",
    "selections": (v1/*: any*/),
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateLabelMutation",
    "selections": (v1/*: any*/)
  },
  "params": {
    "id": "01f658521cc6c78250b2636d2c75f846",
    "metadata": {},
    "name": "updateLabelMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "5bda9d6819d5f7a4b515c22a83f1c73c";

export default node;
