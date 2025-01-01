/**
 * @generated SignedSource<<c6e2eadf2137e218b466c881d23468c4>>
 * @relayHash 60fd6a700a3cf0dc6635db25df42b691
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 60fd6a700a3cf0dc6635db25df42b691

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ReplaceAssigneesForAssignableInput = {
  assignableId: string;
  assigneeIds: ReadonlyArray<string>;
  clientMutationId?: string | null | undefined;
};
export type replaceAssigneesForAssignableMutation$variables = {
  input: ReplaceAssigneesForAssignableInput;
};
export type replaceAssigneesForAssignableMutation$data = {
  readonly replaceAssigneesForAssignable: {
    readonly assignable: {
      readonly assignees: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
      readonly suggestedAssignees: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
  } | null | undefined;
};
export type replaceAssigneesForAssignableMutation$rawResponse = {
  readonly replaceAssigneesForAssignable: {
    readonly assignable: {
      readonly __typename: string;
      readonly __isNode: string;
      readonly assignees: {
        readonly nodes: ReadonlyArray<{
          readonly __typename: "Bot";
          readonly __isActor: "Bot";
          readonly avatarUrl: string;
          readonly id: string;
          readonly isCopilot: boolean;
          readonly login: string;
          readonly name: string | null | undefined;
          readonly profileResourcePath: string | null | undefined;
        } | {
          readonly __typename: "User";
          readonly __isActor: "User";
          readonly avatarUrl: string;
          readonly id: string;
          readonly login: string;
          readonly name: string | null | undefined;
          readonly profileResourcePath: string | null | undefined;
        } | null | undefined> | null | undefined;
      };
      readonly id: string;
      readonly suggestedAssignees: {
        readonly nodes: ReadonlyArray<{
          readonly __typename: "Bot";
          readonly __isActor: "Bot";
          readonly avatarUrl: string;
          readonly id: string;
          readonly isCopilot: boolean;
          readonly login: string;
          readonly name: string | null | undefined;
          readonly profileResourcePath: string | null | undefined;
        } | {
          readonly __typename: "User";
          readonly __isActor: "User";
          readonly avatarUrl: string;
          readonly id: string;
          readonly login: string;
          readonly name: string | null | undefined;
          readonly profileResourcePath: string | null | undefined;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
  } | null | undefined;
};
export type replaceAssigneesForAssignableMutation = {
  rawResponse: replaceAssigneesForAssignableMutation$rawResponse;
  response: replaceAssigneesForAssignableMutation$data;
  variables: replaceAssigneesForAssignableMutation$variables;
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
v2 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 20
  }
],
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v8 = {
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
v9 = {
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
},
v10 = [
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
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/),
              (v5/*: any*/),
              (v6/*: any*/),
              (v7/*: any*/),
              (v8/*: any*/),
              (v9/*: any*/)
            ],
            "type": "Actor",
            "abstractKey": "__isActor"
          }
        ],
        "args": null,
        "argumentDefinitions": ([]/*: any*/)
      }
    ],
    "storageKey": null
  }
],
v11 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "User",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v4/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v3/*: any*/),
          (v5/*: any*/),
          (v6/*: any*/),
          (v7/*: any*/),
          (v8/*: any*/),
          (v9/*: any*/)
        ],
        "type": "Actor",
        "abstractKey": "__isActor"
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
    "name": "replaceAssigneesForAssignableMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ReplaceAssigneesForAssignablePayload",
        "kind": "LinkedField",
        "name": "replaceAssigneesForAssignable",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "assignable",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": (v2/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": (v10/*: any*/),
                "storageKey": "assignees(first:20)"
              },
              {
                "alias": null,
                "args": (v2/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "suggestedAssignees",
                "plural": false,
                "selections": (v10/*: any*/),
                "storageKey": "suggestedAssignees(first:20)"
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
    "name": "replaceAssigneesForAssignableMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ReplaceAssigneesForAssignablePayload",
        "kind": "LinkedField",
        "name": "replaceAssigneesForAssignable",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "assignable",
            "plural": false,
            "selections": [
              (v3/*: any*/),
              {
                "alias": null,
                "args": (v2/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": (v11/*: any*/),
                "storageKey": "assignees(first:20)"
              },
              {
                "alias": null,
                "args": (v2/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "suggestedAssignees",
                "plural": false,
                "selections": (v11/*: any*/),
                "storageKey": "suggestedAssignees(first:20)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/)
                ],
                "type": "Node",
                "abstractKey": "__isNode"
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
    "id": "60fd6a700a3cf0dc6635db25df42b691",
    "metadata": {},
    "name": "replaceAssigneesForAssignableMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "cf977844cd8f6fd52ecb0a04af299f76";

export default node;
