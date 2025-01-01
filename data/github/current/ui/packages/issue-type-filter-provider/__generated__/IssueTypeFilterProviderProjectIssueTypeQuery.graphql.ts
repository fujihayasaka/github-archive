/**
 * @generated SignedSource<<5bc755c5cde412f8de77200baad8edd8>>
 * @relayHash 4ecab7512fd17375c718ee060e7c9130
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4ecab7512fd17375c718ee060e7c9130

import type { ConcreteRequest } from 'relay-runtime';
export type IssueTypeFilterProviderProjectIssueTypeQuery$variables = {
  login: string;
  number: number;
};
export type IssueTypeFilterProviderProjectIssueTypeQuery$data = {
  readonly organization: {
    readonly projectV2: {
      readonly suggestedIssueTypeNames: ReadonlyArray<string> | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type IssueTypeFilterProviderProjectIssueTypeQuery = {
  response: IssueTypeFilterProviderProjectIssueTypeQuery$data;
  variables: IssueTypeFilterProviderProjectIssueTypeQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "login"
  },
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "number"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "login",
    "variableName": "login"
  }
],
v2 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "suggestedIssueTypeNames",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTypeFilterProviderProjectIssueTypeQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Organization",
        "kind": "LinkedField",
        "name": "organization",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v2/*: any*/),
            "concreteType": "ProjectV2",
            "kind": "LinkedField",
            "name": "projectV2",
            "plural": false,
            "selections": [
              (v3/*: any*/)
            ],
            "storageKey": null
          }
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
    "name": "IssueTypeFilterProviderProjectIssueTypeQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Organization",
        "kind": "LinkedField",
        "name": "organization",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v2/*: any*/),
            "concreteType": "ProjectV2",
            "kind": "LinkedField",
            "name": "projectV2",
            "plural": false,
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/)
            ],
            "storageKey": null
          },
          (v4/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "4ecab7512fd17375c718ee060e7c9130",
    "metadata": {},
    "name": "IssueTypeFilterProviderProjectIssueTypeQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "54031af5ea97af051011bdae3b3dc9af";

export default node;
