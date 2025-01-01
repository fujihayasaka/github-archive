/**
 * @generated SignedSource<<35d566eaaa9b2ba838d7f2e7ffb00179>>
 * @relayHash 9d37eb2955c212735990b9b9657ab2cf
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9d37eb2955c212735990b9b9657ab2cf

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type AssigneePickerSearchAssignableRepositoryUsersWithQuery$variables = {
  first: number;
  includeBots?: boolean | null | undefined;
  name: string;
  owner: string;
  query: string;
};
export type AssigneePickerSearchAssignableRepositoryUsersWithQuery$data = {
  readonly repository: {
    readonly assignableUsers: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
      } | null | undefined> | null | undefined;
      readonly totalCount: number;
    };
    readonly installedAppInstallations?: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerInstallationBot">;
      } | null | undefined> | null | undefined;
    };
  } | null | undefined;
};
export type AssigneePickerSearchAssignableRepositoryUsersWithQuery = {
  response: AssigneePickerSearchAssignableRepositoryUsersWithQuery$data;
  variables: AssigneePickerSearchAssignableRepositoryUsersWithQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v1 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "includeBots"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
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
    "name": "first",
    "variableName": "first"
  },
  {
    "kind": "Variable",
    "name": "query",
    "variableName": "query"
  }
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v9 = [
  (v7/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
    "storageKey": null
  },
  (v8/*: any*/),
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
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v11 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slug",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "logoUrl",
  "storageKey": null
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
    "name": "AssigneePickerSearchAssignableRepositoryUsersWithQuery",
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
            "concreteType": "UserConnection",
            "kind": "LinkedField",
            "name": "assignableUsers",
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
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "AssigneePickerAssignee",
                    "selections": (v9/*: any*/),
                    "args": null,
                    "argumentDefinitions": []
                  }
                ],
                "storageKey": null
              },
              (v10/*: any*/)
            ],
            "storageKey": null
          },
          {
            "condition": "includeBots",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": (v11/*: any*/),
                "concreteType": "InstalledAppInstallationsConnection",
                "kind": "LinkedField",
                "name": "installedAppInstallations",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "IntegrationInstallation",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "AssigneePickerInstallationBot",
                        "selections": [
                          (v7/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "App",
                            "kind": "LinkedField",
                            "name": "app",
                            "plural": false,
                            "selections": [
                              (v8/*: any*/),
                              (v12/*: any*/),
                              (v13/*: any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "args": null,
                        "argumentDefinitions": []
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "installedAppInstallations(first:100)"
              }
            ]
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
      (v2/*: any*/),
      (v4/*: any*/),
      (v0/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "AssigneePickerSearchAssignableRepositoryUsersWithQuery",
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
            "concreteType": "UserConnection",
            "kind": "LinkedField",
            "name": "assignableUsers",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "User",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": (v9/*: any*/),
                "storageKey": null
              },
              (v10/*: any*/)
            ],
            "storageKey": null
          },
          {
            "condition": "includeBots",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": (v11/*: any*/),
                "concreteType": "InstalledAppInstallationsConnection",
                "kind": "LinkedField",
                "name": "installedAppInstallations",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "IntegrationInstallation",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v7/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "App",
                        "kind": "LinkedField",
                        "name": "app",
                        "plural": false,
                        "selections": [
                          (v8/*: any*/),
                          (v12/*: any*/),
                          (v13/*: any*/),
                          (v7/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "installedAppInstallations(first:100)"
              }
            ]
          },
          (v7/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "9d37eb2955c212735990b9b9657ab2cf",
    "metadata": {},
    "name": "AssigneePickerSearchAssignableRepositoryUsersWithQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e435e5e1d7a390e33a9933d0c355e327";

export default node;
