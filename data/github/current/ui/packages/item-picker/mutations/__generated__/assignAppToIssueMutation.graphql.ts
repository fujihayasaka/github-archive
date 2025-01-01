/**
 * @generated SignedSource<<9430e4918e99d23fbaaed7ad0c057b34>>
 * @relayHash 3df4609a45c8ad7188dddbd1d20b00a1
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3df4609a45c8ad7188dddbd1d20b00a1

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssignAppToIssueInput = {
  appIds: ReadonlyArray<string>;
  clientMutationId?: string | null | undefined;
  issueId: string;
};
export type assignAppToIssueMutation$variables = {
  input: AssignAppToIssueInput;
};
export type assignAppToIssueMutation$data = {
  readonly assignAppToIssue: {
    readonly issue: {
      readonly assignees: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
      readonly id: string;
      readonly participants: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
  } | null | undefined;
};
export type assignAppToIssueMutation$rawResponse = {
  readonly assignAppToIssue: {
    readonly issue: {
      readonly assignees: {
        readonly nodes: ReadonlyArray<{
          readonly avatarUrl: string;
          readonly id: string;
          readonly login: string;
          readonly name: string | null | undefined;
        } | null | undefined> | null | undefined;
      };
      readonly id: string;
      readonly participants: {
        readonly nodes: ReadonlyArray<{
          readonly avatarUrl: string;
          readonly id: string;
          readonly login: string;
          readonly name: string | null | undefined;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
  } | null | undefined;
};
export type assignAppToIssueMutation = {
  rawResponse: assignAppToIssueMutation$rawResponse;
  response: assignAppToIssueMutation$data;
  variables: assignAppToIssueMutation$variables;
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
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
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
    "value": 20
  }
],
v4 = [
  (v2/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
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
  }
],
v5 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "User",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      {
        "kind": "InlineDataFragmentSpread",
        "name": "AssigneePickerAssignee",
        "selections": (v4/*: any*/),
        "args": null,
        "argumentDefinitions": ([]/*: any*/)
      }
    ],
    "storageKey": null
  }
],
v6 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v7 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "User",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": (v4/*: any*/),
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "assignAppToIssueMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "AssignAppToIssuePayload",
        "kind": "LinkedField",
        "name": "assignAppToIssue",
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
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": (v5/*: any*/),
                "storageKey": "assignees(first:20)"
              },
              {
                "alias": null,
                "args": (v6/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "participants",
                "plural": false,
                "selections": (v5/*: any*/),
                "storageKey": "participants(first:10)"
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
    "name": "assignAppToIssueMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "AssignAppToIssuePayload",
        "kind": "LinkedField",
        "name": "assignAppToIssue",
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
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": (v7/*: any*/),
                "storageKey": "assignees(first:20)"
              },
              {
                "alias": null,
                "args": (v6/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "participants",
                "plural": false,
                "selections": (v7/*: any*/),
                "storageKey": "participants(first:10)"
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
    "id": "3df4609a45c8ad7188dddbd1d20b00a1",
    "metadata": {},
    "name": "assignAppToIssueMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "6c8dbfd680c2d6135776ed99683e4b93";

export default node;
