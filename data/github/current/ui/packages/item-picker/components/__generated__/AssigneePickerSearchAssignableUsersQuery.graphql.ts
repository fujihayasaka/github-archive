/**
 * @generated SignedSource<<db68a15948b2f41a85eccf4885d98e56>>
 * @relayHash bd8107ea164f1f5859481d7e56bfd9c0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID bd8107ea164f1f5859481d7e56bfd9c0

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneePickerSearchAssignableUsersQuery$variables = {
  first: number;
  name: string;
  number: number;
  owner: string;
  query: string;
};
export type AssigneePickerSearchAssignableUsersQuery$data = {
  readonly repository: {
    readonly issueOrPullRequest: {
      readonly suggestedActors?: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
  } | null | undefined;
};
export type AssigneePickerSearchAssignableUsersQuery = {
  response: AssigneePickerSearchAssignableUsersQuery$data;
  variables: AssigneePickerSearchAssignableUsersQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "query"
},
v5 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "name"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v6 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v7 = [
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "first"
  },
  {
    "kind": "Variable",
    "name": "query",
    "variableName": "query"
  }
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v13 = {
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
v14 = {
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
v15 = {
  "kind": "InlineFragment",
  "selections": [
    (v9/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "AssigneePickerSearchAssignableUsersQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v6/*: any*/),
            "concreteType": null,
            "kind": "LinkedField",
            "name": "issueOrPullRequest",
            "plural": false,
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v7/*: any*/),
                    "concreteType": "AssigneeConnection",
                    "kind": "LinkedField",
                    "name": "suggestedActors",
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
                          {
                            "kind": "InlineDataFragmentSpread",
                            "name": "AssigneePickerAssignee",
                            "selections": [
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v8/*: any*/),
                                  (v9/*: any*/),
                                  (v10/*: any*/),
                                  (v11/*: any*/),
                                  (v12/*: any*/),
                                  (v13/*: any*/),
                                  (v14/*: any*/)
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
                    "storageKey": null
                  }
                ],
                "type": "Assignable",
                "abstractKey": "__isAssignable"
              }
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
    "argumentDefinitions": [
      (v3/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v4/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "AssigneePickerSearchAssignableUsersQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v6/*: any*/),
            "concreteType": null,
            "kind": "LinkedField",
            "name": "issueOrPullRequest",
            "plural": false,
            "selections": [
              (v8/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v7/*: any*/),
                    "concreteType": "AssigneeConnection",
                    "kind": "LinkedField",
                    "name": "suggestedActors",
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
                          (v8/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v9/*: any*/),
                              (v10/*: any*/),
                              (v11/*: any*/),
                              (v12/*: any*/),
                              (v13/*: any*/),
                              (v14/*: any*/)
                            ],
                            "type": "Actor",
                            "abstractKey": "__isActor"
                          },
                          (v15/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Assignable",
                "abstractKey": "__isAssignable"
              },
              (v15/*: any*/)
            ],
            "storageKey": null
          },
          (v9/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "bd8107ea164f1f5859481d7e56bfd9c0",
    "metadata": {},
    "name": "AssigneePickerSearchAssignableUsersQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "c802b049c47d612312ea7cc61053c9ea";

export default node;
