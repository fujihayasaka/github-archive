/**
 * @generated SignedSource<<a9cddbf5b6416f3a94eb0614b07d5d69>>
 * @relayHash e217341def0be54888c037d5b64f6889
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID e217341def0be54888c037d5b64f6889

import type { ConcreteRequest } from 'relay-runtime';
export type DependenciesPickerBlockingBlockedByIssuesQuery$variables = {
  id: string;
};
export type DependenciesPickerBlockingBlockedByIssuesQuery$data = {
  readonly node: {
    readonly blockedBy?: {
      readonly nodes: ReadonlyArray<{
        readonly id: string;
      } | null | undefined> | null | undefined;
    };
    readonly blocking?: {
      readonly nodes: ReadonlyArray<{
        readonly id: string;
      } | null | undefined> | null | undefined;
    };
    readonly id?: string;
  } | null | undefined;
};
export type DependenciesPickerBlockingBlockedByIssuesQuery = {
  response: DependenciesPickerBlockingBlockedByIssuesQuery$data;
  variables: DependenciesPickerBlockingBlockedByIssuesQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v4 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v2/*: any*/)
    ],
    "storageKey": null
  }
],
v5 = {
  "alias": null,
  "args": (v3/*: any*/),
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "blockedBy",
  "plural": false,
  "selections": (v4/*: any*/),
  "storageKey": "blockedBy(first:100)"
},
v6 = {
  "alias": null,
  "args": (v3/*: any*/),
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "blocking",
  "plural": false,
  "selections": (v4/*: any*/),
  "storageKey": "blocking(first:100)"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "DependenciesPickerBlockingBlockedByIssuesQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v2/*: any*/),
              (v5/*: any*/),
              (v6/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
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
    "name": "DependenciesPickerBlockingBlockedByIssuesQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v6/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "e217341def0be54888c037d5b64f6889",
    "metadata": {},
    "name": "DependenciesPickerBlockingBlockedByIssuesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "5256acc8a89667f2e629c973029c8f67";

export default node;
