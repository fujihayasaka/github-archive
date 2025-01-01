/**
 * @generated SignedSource<<7e8e74f85c40888bac0afd23f20ecc2d>>
 * @relayHash 0489a1b29f7cb40b303417117c2ed3eb
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 0489a1b29f7cb40b303417117c2ed3eb

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SearchPaginatedQuery$variables = {
  cursor?: string | null | undefined;
  fetchRepository: boolean;
  first?: number | null | undefined;
  id: string;
  includeGitData?: boolean | null | undefined;
  labelPageSize: number;
  query: string;
  skip?: number | null | undefined;
};
export type SearchPaginatedQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"ListItemsPaginated_results">;
  } | null | undefined;
};
export type SearchPaginatedQuery = {
  response: SearchPaginatedQuery$data;
  variables: SearchPaginatedQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "cursor"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "fetchRepository"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v4 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "includeGitData"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "labelPageSize"
},
v6 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "query"
},
v7 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "skip"
},
v8 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v9 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v10 = {
  "kind": "Variable",
  "name": "query",
  "variableName": "query"
},
v11 = {
  "kind": "Variable",
  "name": "skip",
  "variableName": "skip"
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v14 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "cursor"
  },
  (v9/*: any*/),
  (v10/*: any*/),
  (v11/*: any*/),
  {
    "kind": "Literal",
    "name": "type",
    "value": "ISSUE_ADVANCED"
  }
],
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": [
    {
      "kind": "Variable",
      "name": "first",
      "variableName": "labelPageSize"
    },
    {
      "kind": "Literal",
      "name": "orderBy",
      "value": {
        "direction": "ASC",
        "field": "NAME"
      }
    }
  ],
  "concreteType": "LabelConnection",
  "kind": "LinkedField",
  "name": "labels",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "Label",
      "kind": "LinkedField",
      "name": "nodes",
      "plural": true,
      "selections": [
        (v13/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        (v18/*: any*/),
        (v17/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "description",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v24/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": null
    },
    (v13/*: any*/)
  ],
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v27 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v16/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "url",
        "storageKey": null
      },
      (v13/*: any*/)
    ],
    "storageKey": null
  }
],
v28 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v27/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v27/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v29 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v20/*: any*/),
    (v21/*: any*/),
    (v22/*: any*/),
    (v23/*: any*/),
    (v25/*: any*/),
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "enableDuplicate",
          "value": true
        }
      ],
      "kind": "ScalarField",
      "name": "stateReason",
      "storageKey": "stateReason(enableDuplicate:true)"
    },
    (v26/*: any*/),
    (v28/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reviewDecision",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v33 = {
  "alias": "pullRequestState",
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        (v12/*: any*/),
        (v24/*: any*/),
        (v13/*: any*/)
      ],
      "storageKey": null
    },
    (v13/*: any*/)
  ],
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "concreteType": "StatusCheckRollup",
  "kind": "LinkedField",
  "name": "statusCheckRollup",
  "plural": false,
  "selections": [
    (v26/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "StatusCheckRollupContextConnection",
      "kind": "LinkedField",
      "name": "contexts",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "checkRunCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "CheckRunStateCount",
          "kind": "LinkedField",
          "name": "checkRunCountsByState",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "count",
              "storageKey": null
            },
            (v26/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v13/*: any*/)
  ],
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/),
      (v7/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "SearchPaginatedQuery",
    "selections": [
      {
        "alias": null,
        "args": (v8/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "cursor",
                "variableName": "cursor"
              },
              {
                "kind": "Variable",
                "name": "fetchRepository",
                "variableName": "fetchRepository"
              },
              (v9/*: any*/),
              {
                "kind": "Variable",
                "name": "includeGitData",
                "variableName": "includeGitData"
              },
              {
                "kind": "Variable",
                "name": "labelPageSize",
                "variableName": "labelPageSize"
              },
              (v10/*: any*/),
              (v11/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "ListItemsPaginated_results"
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
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/),
      (v7/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Operation",
    "name": "SearchPaginatedQuery",
    "selections": [
      {
        "alias": null,
        "args": (v8/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v12/*: any*/),
          (v13/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v14/*: any*/),
                "concreteType": "SearchResultItemConnection",
                "kind": "LinkedField",
                "name": "search",
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
                    "if": null,
                    "kind": "Stream",
                    "label": "ListItemsPaginated_results$stream$Query_search",
                    "selections": [
                      {
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
                              (v12/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v13/*: any*/),
                                  (v15/*: any*/),
                                  (v16/*: any*/),
                                  {
                                    "alias": "titleHtml",
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "titleHTML",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "IssueType",
                                    "kind": "LinkedField",
                                    "name": "issueType",
                                    "plural": false,
                                    "selections": [
                                      (v13/*: any*/),
                                      (v17/*: any*/),
                                      (v18/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v29/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v19/*: any*/),
                                          (v20/*: any*/),
                                          (v21/*: any*/),
                                          (v22/*: any*/),
                                          (v23/*: any*/),
                                          (v25/*: any*/),
                                          (v30/*: any*/),
                                          (v31/*: any*/),
                                          (v32/*: any*/),
                                          (v33/*: any*/),
                                          (v28/*: any*/)
                                        ],
                                        "type": "PullRequest",
                                        "abstractKey": null
                                      }
                                    ],
                                    "type": "IssueOrPullRequest",
                                    "abstractKey": "__isIssueOrPullRequest"
                                  },
                                  {
                                    "condition": "fetchRepository",
                                    "kind": "Condition",
                                    "passingValue": true,
                                    "selections": [
                                      (v34/*: any*/)
                                    ]
                                  }
                                ],
                                "type": "Issue",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v13/*: any*/),
                                  (v15/*: any*/),
                                  (v34/*: any*/),
                                  (v16/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "titleHTML",
                                    "storageKey": null
                                  },
                                  {
                                    "condition": "includeGitData",
                                    "kind": "Condition",
                                    "passingValue": true,
                                    "selections": [
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": "PullRequestCommit",
                                        "kind": "LinkedField",
                                        "name": "headCommit",
                                        "plural": false,
                                        "selections": [
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "Commit",
                                            "kind": "LinkedField",
                                            "name": "commit",
                                            "plural": false,
                                            "selections": [
                                              (v13/*: any*/),
                                              (v35/*: any*/)
                                            ],
                                            "storageKey": null
                                          },
                                          (v13/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v35/*: any*/)
                                    ]
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v29/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v19/*: any*/),
                                          (v20/*: any*/),
                                          (v21/*: any*/),
                                          (v22/*: any*/),
                                          (v23/*: any*/),
                                          (v25/*: any*/),
                                          (v31/*: any*/),
                                          (v33/*: any*/),
                                          (v28/*: any*/),
                                          {
                                            "condition": "includeGitData",
                                            "kind": "Condition",
                                            "passingValue": true,
                                            "selections": [
                                              (v30/*: any*/),
                                              (v32/*: any*/)
                                            ]
                                          }
                                        ],
                                        "type": "PullRequest",
                                        "abstractKey": null
                                      }
                                    ],
                                    "type": "IssueOrPullRequest",
                                    "abstractKey": "__isIssueOrPullRequest"
                                  }
                                ],
                                "type": "PullRequest",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v13/*: any*/)
                                ],
                                "type": "Node",
                                "abstractKey": "__isNode"
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
                      }
                    ]
                  },
                  {
                    "if": null,
                    "kind": "Defer",
                    "label": "ListItemsPaginated_results$defer$Query_search$pageInfo",
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
              {
                "alias": null,
                "args": (v14/*: any*/),
                "filters": [
                  "query",
                  "type",
                  "skip"
                ],
                "handle": "connection",
                "key": "Query_search",
                "kind": "LinkedHandle",
                "name": "search"
              },
              {
                "kind": "TypeDiscriminator",
                "abstractKey": "__isNode"
              }
            ],
            "type": "Searchable",
            "abstractKey": "__isSearchable"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "0489a1b29f7cb40b303417117c2ed3eb",
    "metadata": {},
    "name": "SearchPaginatedQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e63a8c38b74a1ac19e6465c95034dc8a";

export default node;
