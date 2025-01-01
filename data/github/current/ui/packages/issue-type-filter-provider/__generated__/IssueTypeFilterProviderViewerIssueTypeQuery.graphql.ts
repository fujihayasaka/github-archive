/**
 * @generated SignedSource<<e97139325d8cbb65e47a79947e56dc62>>
 * @relayHash 58ebbad60258ea0c9eb795e67cc2b575
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 58ebbad60258ea0c9eb795e67cc2b575

import type { ConcreteRequest } from 'relay-runtime';
export type IssueTypeFilterProviderViewerIssueTypeQuery$variables = Record<PropertyKey, never>;
export type IssueTypeFilterProviderViewerIssueTypeQuery$data = {
  readonly viewer: {
    readonly suggestedIssueTypeNames: ReadonlyArray<string> | null | undefined;
  };
};
export type IssueTypeFilterProviderViewerIssueTypeQuery = {
  response: IssueTypeFilterProviderViewerIssueTypeQuery$data;
  variables: IssueTypeFilterProviderViewerIssueTypeQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "suggestedIssueTypeNames",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTypeFilterProviderViewerIssueTypeQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          (v0/*: any*/)
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueTypeFilterProviderViewerIssueTypeQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          (v0/*: any*/),
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
    "id": "58ebbad60258ea0c9eb795e67cc2b575",
    "metadata": {},
    "name": "IssueTypeFilterProviderViewerIssueTypeQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "765a25834ce6bc541a1d98b6355cf514";

export default node;
