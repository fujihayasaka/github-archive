/**
 * @generated SignedSource<<d367e556b6e93e09a046fc7567a4217e>>
 * @relayHash 09dadc4001d02695ae13e106fb7c5922
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 09dadc4001d02695ae13e106fb7c5922

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ReplaceActorsForAssignableInput = {
  actorIds: ReadonlyArray<string>;
  assignableId: string;
  clientMutationId?: string | null | undefined;
};
export type replaceActorsForAssignableMutation$variables = {
  input: ReplaceActorsForAssignableInput;
};
export type replaceActorsForAssignableMutation$data = {
  readonly replaceActorsForAssignable: {
    readonly assignable: {
      readonly assignedActors?: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
      readonly id?: string;
      readonly participants?: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
  } | null | undefined;
};
export type replaceActorsForAssignableMutation$rawResponse = {
  readonly replaceActorsForAssignable: {
    readonly assignable: {
      readonly __typename: "Issue";
      readonly __isNode: "Issue";
      readonly assignedActors: {
        readonly nodes: ReadonlyArray<{
          readonly __typename: "Bot";
          readonly __isActor: "Bot";
          readonly __isNode: "Bot";
          readonly avatarUrl: string;
          readonly id: string;
          readonly isCopilot: boolean;
          readonly login: string;
          readonly name: string | null | undefined;
          readonly profileResourcePath: string | null | undefined;
        } | {
          readonly __typename: string;
          readonly __isActor: string;
          readonly __isNode: string;
          readonly avatarUrl: string;
          readonly id: string;
          readonly login: string;
          readonly name: string | null | undefined;
          readonly profileResourcePath: string | null | undefined;
        } | null | undefined> | null | undefined;
      };
      readonly id: string;
      readonly participants: {
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
    } | {
      readonly __typename: string;
      readonly __isNode: string;
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type replaceActorsForAssignableMutation = {
  rawResponse: replaceActorsForAssignableMutation$rawResponse;
  response: replaceActorsForAssignableMutation$data;
  variables: replaceActorsForAssignableMutation$variables;
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
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
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
    "kind": "InlineDataFragmentSpread",
    "name": "AssigneePickerAssignee",
    "selections": [
      {
        "kind": "InlineFragment",
        "selections": [
          (v4/*: any*/),
          (v2/*: any*/),
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
v11 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v12 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "replaceActorsForAssignableMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ReplaceActorsForAssignablePayload",
        "kind": "LinkedField",
        "name": "replaceActorsForAssignable",
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
                "kind": "InlineFragment",
                "selections": [
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": (v3/*: any*/),
                    "concreteType": "AssigneeConnection",
                    "kind": "LinkedField",
                    "name": "assignedActors",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": (v10/*: any*/),
                        "storageKey": null
                      }
                    ],
                    "storageKey": "assignedActors(first:20)"
                  },
                  {
                    "alias": null,
                    "args": (v11/*: any*/),
                    "concreteType": "UserConnection",
                    "kind": "LinkedField",
                    "name": "participants",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "User",
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": (v10/*: any*/),
                        "storageKey": null
                      }
                    ],
                    "storageKey": "participants(first:10)"
                  }
                ],
                "type": "Issue",
                "abstractKey": null
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
    "name": "replaceActorsForAssignableMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ReplaceActorsForAssignablePayload",
        "kind": "LinkedField",
        "name": "replaceActorsForAssignable",
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
              (v4/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": (v3/*: any*/),
                    "concreteType": "AssigneeConnection",
                    "kind": "LinkedField",
                    "name": "assignedActors",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          (v4/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v2/*: any*/),
                              (v5/*: any*/),
                              (v6/*: any*/),
                              (v7/*: any*/),
                              (v8/*: any*/),
                              (v9/*: any*/)
                            ],
                            "type": "Actor",
                            "abstractKey": "__isActor"
                          },
                          (v12/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "assignedActors(first:20)"
                  },
                  {
                    "alias": null,
                    "args": (v11/*: any*/),
                    "concreteType": "UserConnection",
                    "kind": "LinkedField",
                    "name": "participants",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "User",
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          (v2/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
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
                        "storageKey": null
                      }
                    ],
                    "storageKey": "participants(first:10)"
                  }
                ],
                "type": "Issue",
                "abstractKey": null
              },
              (v12/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "09dadc4001d02695ae13e106fb7c5922",
    "metadata": {},
    "name": "replaceActorsForAssignableMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "e04ca48f11321b27476efd542934d163";

export default node;
