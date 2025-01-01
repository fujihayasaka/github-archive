/**
 * @generated SignedSource<<a22d81b7fa6e45741b76389fa4ebce40>>
 * @relayHash a6677fa25f66fdc23d4dbe44f4e62757
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a6677fa25f66fdc23d4dbe44f4e62757

import { ConcreteRequest } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type updateIssueStateMutation$variables = {
  id: string;
};
export type updateIssueStateMutation$data = {
  readonly reopenIssue: {
    readonly issue: {
      readonly duplicateOf: {
        readonly number: number;
        readonly url: string;
      } | null | undefined;
      readonly id: string;
      readonly state: IssueState;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueStateMutation$rawResponse = {
  readonly reopenIssue: {
    readonly issue: {
      readonly duplicateOf: {
        readonly id: string;
        readonly number: number;
        readonly url: string;
      } | null | undefined;
      readonly id: string;
      readonly state: IssueState;
    } | null | undefined;
  } | null | undefined;
};
export type updateIssueStateMutation = {
  rawResponse: updateIssueStateMutation$rawResponse;
  response: updateIssueStateMutation$data;
  variables: updateIssueStateMutation$variables;
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
    "fields": [
      {
        "kind": "Variable",
        "name": "issueId",
        "variableName": "id"
      }
    ],
    "kind": "ObjectValue",
    "name": "input"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "updateIssueStateMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ReopenIssuePayload",
        "kind": "LinkedField",
        "name": "reopenIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v5/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "updateIssueStateMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ReopenIssuePayload",
        "kind": "LinkedField",
        "name": "reopenIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v5/*: any*/),
                  (v2/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "a6677fa25f66fdc23d4dbe44f4e62757",
    "metadata": {},
    "name": "updateIssueStateMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "ca935e60ecf589dc4afd48ce97e1708b";

export default node;
