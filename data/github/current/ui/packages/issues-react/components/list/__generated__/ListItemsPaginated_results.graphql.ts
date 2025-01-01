/**
 * @generated SignedSource<<1b80748bffe7f3fa053b37ebecd0d0a8>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs, Result } from "relay-runtime";
export type ListItemsPaginated_results$data = {
  readonly id?: string;
  readonly search: Result<{
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly __typename: "Issue";
        readonly id: string;
        readonly number: number;
        readonly " $fragmentSpreads": FragmentRefs<"IssueRow">;
      } | {
        readonly __typename: "PullRequest";
        readonly id: string;
        readonly number: number;
        readonly " $fragmentSpreads": FragmentRefs<"PullRequestRow_pullRequest">;
      } | {
        // This will never be '%other', but we need some
        // value in case none of the concrete values match.
        readonly __typename: "%other";
      } | null | undefined;
    } | null | undefined>;
    readonly issueCount: number;
    readonly pageInfo: {
      readonly endCursor: string | null | undefined;
      readonly hasNextPage: boolean;
      readonly hasPreviousPage: boolean;
      readonly startCursor: string | null | undefined;
    };
  }, unknown>;
  readonly " $fragmentType": "ListItemsPaginated_results";
};
export type ListItemsPaginated_results$key = {
  readonly " $data"?: ListItemsPaginated_results$data;
  readonly " $fragmentSpreads": FragmentRefs<"ListItemsPaginated_results">;
};

import SearchPaginatedQuery_graphql from './SearchPaginatedQuery.graphql';

const node: ReaderFragment = (function(){
var v0 = [
  "search"
],
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
  "name": "number",
  "storageKey": null
},
v3 = {
  "kind": "Variable",
  "name": "labelPageSize",
  "variableName": "labelPageSize"
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "cursor"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "fetchRepository"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "first"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "includeGitData"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "labelPageSize"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "query"
    },
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "skip"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "first",
        "cursor": "cursor",
        "direction": "forward",
        "path": (v0/*: any*/),
        "stream": true
      }
    ],
    "refetch": {
      "connection": {
        "forward": {
          "count": "first",
          "cursor": "cursor"
        },
        "backward": null,
        "path": (v0/*: any*/)
      },
      "fragmentPathInResult": [
        "node"
      ],
      "operation": SearchPaginatedQuery_graphql,
      "identifierInfo": {
        "identifierField": "id",
        "identifierQueryVariableName": "id"
      }
    }
  },
  "name": "ListItemsPaginated_results",
  "selections": [
    {
      "kind": "CatchField",
      "field": {
        "alias": "search",
        "args": [
          {
            "kind": "Variable",
            "name": "query",
            "variableName": "query"
          },
          {
            "kind": "Variable",
            "name": "skip",
            "variableName": "skip"
          },
          {
            "kind": "Literal",
            "name": "type",
            "value": "ISSUE_ADVANCED"
          }
        ],
        "concreteType": "SearchResultItemConnection",
        "kind": "LinkedField",
        "name": "__Query_search_connection",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "issueCount",
            "storageKey": null
          },
          {
            "kind": "Stream",
            "selections": [
              {
                "kind": "RequiredField",
                "field": {
                  "alias": null,
                  "args": null,
                  "concreteType": "SearchResultItemEdge",
                  "kind": "LinkedField",
                  "name": "edges",
                  "plural": true,
                  "selections": [
                    {
                      "alias": null,
                      "args": null,
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
                        {
                          "kind": "InlineFragment",
                          "selections": [
                            (v1/*: any*/),
                            (v2/*: any*/),
                            {
                              "args": [
                                {
                                  "kind": "Variable",
                                  "name": "fetchRepository",
                                  "variableName": "fetchRepository"
                                },
                                (v3/*: any*/)
                              ],
                              "kind": "FragmentSpread",
                              "name": "IssueRow"
                            }
                          ],
                          "type": "Issue",
                          "abstractKey": null
                        },
                        {
                          "kind": "InlineFragment",
                          "selections": [
                            (v1/*: any*/),
                            (v2/*: any*/),
                            {
                              "args": [
                                {
                                  "kind": "Variable",
                                  "name": "includeGitData",
                                  "variableName": "includeGitData"
                                },
                                (v3/*: any*/)
                              ],
                              "kind": "FragmentSpread",
                              "name": "PullRequestRow_pullRequest"
                            }
                          ],
                          "type": "PullRequest",
                          "abstractKey": null
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
                "action": "THROW"
              }
            ]
          },
          {
            "kind": "Defer",
            "selections": [
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
                    "name": "startCursor",
                    "storageKey": null
                  },
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
                    "name": "hasPreviousPage",
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
            ]
          }
        ],
        "storageKey": null
      },
      "to": "RESULT"
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v1/*: any*/)
      ],
      "type": "Node",
      "abstractKey": "__isNode"
    }
  ],
  "type": "Searchable",
  "abstractKey": "__isSearchable"
};
})();

(node as any).hash = "7048a8fa4213ea495d3a363ede290f47";

export default node;
