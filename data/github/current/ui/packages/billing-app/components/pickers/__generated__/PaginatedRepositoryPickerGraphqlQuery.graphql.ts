/**
 * @generated SignedSource<<3798ffa7b837df931eaca3cf48220c3b>>
 * @relayHash 31f8102476b6bc7c91759823ef838b7f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 31f8102476b6bc7c91759823ef838b7f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PaginatedRepositoryPickerGraphqlQuery$variables = {
  phrase?: string | null | undefined;
  slug: string;
};
export type PaginatedRepositoryPickerGraphqlQuery$data = {
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"PaginatedRepositoryPickerRepos">;
  };
};
export type PaginatedRepositoryPickerGraphqlQuery = {
  response: PaginatedRepositoryPickerGraphqlQuery$data;
  variables: PaginatedRepositoryPickerGraphqlQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "phrase"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "slug"
},
v2 = {
  "kind": "Literal",
  "name": "excludeArchived",
  "value": true
},
v3 = {
  "kind": "Variable",
  "name": "phrase",
  "variableName": "phrase"
},
v4 = {
  "kind": "Variable",
  "name": "slug",
  "variableName": "slug"
},
v5 = [
  (v2/*: any*/),
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  },
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "DESC",
      "field": "CREATED_AT"
    }
  },
  (v3/*: any*/),
  (v4/*: any*/)
],
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "PaginatedRepositoryPickerGraphqlQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "args": [
              (v2/*: any*/),
              (v3/*: any*/),
              (v4/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "PaginatedRepositoryPickerRepos"
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
      (v1/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "PaginatedRepositoryPickerGraphqlQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v5/*: any*/),
            "concreteType": "RepositoryConnection",
            "kind": "LinkedField",
            "name": "enterpriseRepositories",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "RepositoryEdge",
                "kind": "LinkedField",
                "name": "edges",
                "plural": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "node",
                    "plural": false,
                    "selections": [
                      (v6/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "nameWithOwner",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isPrivate",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isArchived",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "__typename",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "cursor",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "totalCount",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "PageInfo",
                "kind": "LinkedField",
                "name": "pageInfo",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "endCursor",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "hasNextPage",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": (v5/*: any*/),
            "filters": [
              "phrase",
              "slug",
              "orderBy",
              "excludeArchived"
            ],
            "handle": "connection",
            "key": "PaginatedRepositoryListFragment_enterpriseRepositories",
            "kind": "LinkedHandle",
            "name": "enterpriseRepositories"
          },
          (v6/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "31f8102476b6bc7c91759823ef838b7f",
    "metadata": {},
    "name": "PaginatedRepositoryPickerGraphqlQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "9131da1723980f06b5e6a67cc6bb2994";

export default node;
