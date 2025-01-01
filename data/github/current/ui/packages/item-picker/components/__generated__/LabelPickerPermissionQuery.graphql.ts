/**
 * @generated SignedSource<<6ee6566ef67c366b28df3c004da015eb>>
 * @relayHash e60f1995c53fa2376cdc9daecf2d8d93
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID e60f1995c53fa2376cdc9daecf2d8d93

import type { ConcreteRequest } from 'relay-runtime';
export type LabelPickerPermissionQuery$variables = {
  owner: string;
  repo: string;
};
export type LabelPickerPermissionQuery$data = {
  readonly repository: {
    readonly viewerIssueCreationPermissions: {
      readonly labelable: boolean;
    };
  } | null | undefined;
};
export type LabelPickerPermissionQuery = {
  response: LabelPickerPermissionQuery$data;
  variables: LabelPickerPermissionQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "owner"
  },
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "repo"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueCreationPermissions",
  "kind": "LinkedField",
  "name": "viewerIssueCreationPermissions",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "labelable",
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "LabelPickerPermissionQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v2/*: any*/)
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "LabelPickerPermissionQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
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
      }
    ]
  },
  "params": {
    "id": "e60f1995c53fa2376cdc9daecf2d8d93",
    "metadata": {},
    "name": "LabelPickerPermissionQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "4a622bc23fd8b89eeafc34a5dbf3e987";

export default node;
