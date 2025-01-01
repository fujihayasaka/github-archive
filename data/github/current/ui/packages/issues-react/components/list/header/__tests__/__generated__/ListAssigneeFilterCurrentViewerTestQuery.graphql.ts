/**
 * @generated SignedSource<<21fecd1f8e8074ff6b3e2050e06d768b>>
 * @relayHash 49eede84bf8c659a2adef39a53022771
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 49eede84bf8c659a2adef39a53022771

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListAssigneeFilterCurrentViewerTestQuery$variables = Record<PropertyKey, never>;
export type ListAssigneeFilterCurrentViewerTestQuery$data = {
  readonly safeViewer: {
    readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
  } | null | undefined;
};
export type ListAssigneeFilterCurrentViewerTestQuery = {
  response: ListAssigneeFilterCurrentViewerTestQuery$data;
  variables: ListAssigneeFilterCurrentViewerTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "size",
      "value": 64
    }
  ],
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": "avatarUrl(size:64)"
},
v6 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isCopilot",
      "storageKey": null
    }
  ],
  "type": "Bot",
  "abstractKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "ListAssigneeFilterCurrentViewerTestQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "safeViewer",
        "plural": false,
        "selections": [
          {
            "kind": "InlineDataFragmentSpread",
            "name": "AssigneePickerAssignee",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  (v0/*: any*/),
                  (v1/*: any*/),
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v5/*: any*/),
                  (v6/*: any*/)
                ],
                "type": "Actor",
                "abstractKey": "__isActor"
              }
            ],
            "args": null,
            "argumentDefinitions": []
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
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "ListAssigneeFilterCurrentViewerTestQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "safeViewer",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v0/*: any*/),
              (v2/*: any*/),
              (v3/*: any*/),
              (v4/*: any*/),
              (v5/*: any*/),
              (v6/*: any*/)
            ],
            "type": "Actor",
            "abstractKey": "__isActor"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "49eede84bf8c659a2adef39a53022771",
    "metadata": {},
    "name": "ListAssigneeFilterCurrentViewerTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "6b691d5a1923e97815735a0d8ae9ba22";

export default node;
