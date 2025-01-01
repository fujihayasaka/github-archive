/**
 * @generated SignedSource<<03d06217822861a7584466094b03bc5d>>
 * @relayHash eada1d8465212306d51e35765903297b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID eada1d8465212306d51e35765903297b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueIndexPageQuery$variables = {
  first?: number | null | undefined;
  labelPageSize?: number | null | undefined;
  name: string;
  owner: string;
  query?: string | null | undefined;
  skip?: number | null | undefined;
};
export type IssueIndexPageQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"FirstTimeContributionBanner" | "ListQuery" | "ListRepositoryFragment" | "PinnedIssues">;
  } | null | undefined;
  readonly safeViewer: {
    readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
  } | null | undefined;
};
export type IssueIndexPageQuery = {
  response: IssueIndexPageQuery$data;
  variables: IssueIndexPageQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": 25,
  "kind": "LocalArgument",
  "name": "first"
},
v1 = {
  "defaultValue": 20,
  "kind": "LocalArgument",
  "name": "labelPageSize"
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
  "defaultValue": "state:open archived:false assignee:@me sort:updated-desc",
  "kind": "LocalArgument",
  "name": "query"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "skip"
},
v6 = [
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
v7 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v8 = {
  "kind": "Variable",
  "name": "query",
  "variableName": "query"
},
v9 = {
  "kind": "Variable",
  "name": "skip",
  "variableName": "skip"
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v15 = {
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
v16 = {
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
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
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
  "name": "state",
  "storageKey": null
},
v22 = {
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
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanPinIssues",
  "storageKey": null
},
v25 = [
  (v7/*: any*/),
  (v8/*: any*/),
  (v9/*: any*/),
  {
    "kind": "Literal",
    "name": "type",
    "value": "ISSUE_ADVANCED"
  }
],
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v27 = {
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
        (v11/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        (v26/*: any*/),
        (v13/*: any*/),
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
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "resourcePath",
      "storageKey": null
    },
    (v10/*: any*/),
    (v16/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v32 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v17/*: any*/),
      (v19/*: any*/),
      (v11/*: any*/)
    ],
    "storageKey": null
  }
],
v33 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v32/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v32/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v27/*: any*/),
    (v20/*: any*/),
    (v28/*: any*/),
    (v29/*: any*/),
    (v30/*: any*/),
    (v31/*: any*/),
    (v22/*: any*/),
    (v21/*: any*/),
    (v33/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v36 = {
  "alias": "pullRequestState",
  "args": null,
  "kind": "ScalarField",
  "name": "state",
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
      (v5/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueIndexPageQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "PinnedIssues"
          },
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "ListRepositoryFragment"
          },
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "FirstTimeContributionBanner"
          },
          {
            "args": [
              {
                "kind": "Literal",
                "name": "fetchRepository",
                "value": false
              },
              (v7/*: any*/),
              {
                "kind": "Variable",
                "name": "labelPageSize",
                "variableName": "labelPageSize"
              },
              (v8/*: any*/),
              (v9/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "ListQuery"
          }
        ],
        "storageKey": null
      },
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
                  (v10/*: any*/),
                  (v11/*: any*/),
                  (v12/*: any*/),
                  (v13/*: any*/),
                  (v14/*: any*/),
                  (v15/*: any*/),
                  (v16/*: any*/)
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
    "argumentDefinitions": [
      (v4/*: any*/),
      (v0/*: any*/),
      (v1/*: any*/),
      (v5/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueIndexPageQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v11/*: any*/),
          {
            "alias": null,
            "args": [
              {
                "kind": "Literal",
                "name": "first",
                "value": 3
              }
            ],
            "concreteType": "PinnedIssueConnection",
            "kind": "LinkedField",
            "name": "pinnedIssues",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "PinnedIssue",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": [
                  (v11/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Issue",
                    "kind": "LinkedField",
                    "name": "issue",
                    "plural": false,
                    "selections": [
                      (v11/*: any*/),
                      (v17/*: any*/),
                      (v18/*: any*/),
                      (v19/*: any*/),
                      (v20/*: any*/),
                      (v21/*: any*/),
                      (v22/*: any*/),
                      (v23/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "author",
                        "plural": false,
                        "selections": [
                          (v10/*: any*/),
                          (v12/*: any*/),
                          (v19/*: any*/),
                          (v11/*: any*/)
                        ],
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "totalCommentsCount",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v24/*: any*/),
                          (v11/*: any*/)
                        ],
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
                "args": null,
                "kind": "ScalarField",
                "name": "totalCount",
                "storageKey": null
              }
            ],
            "storageKey": "pinnedIssues(first:3)"
          },
          (v24/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "viewerCanPush",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isDisabled",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isLocked",
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
            "name": "isInOrganization",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isOwnerEnterpriseManaged",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameWithOwner",
            "storageKey": null
          },
          {
            "alias": null,
            "args": [
              {
                "kind": "Literal",
                "name": "isPullRequests",
                "value": false
              }
            ],
            "kind": "ScalarField",
            "name": "showFirstTimeContributorBanner",
            "storageKey": "showFirstTimeContributorBanner(isPullRequests:false)"
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "CommunityProfile",
            "kind": "LinkedField",
            "name": "communityProfile",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "goodFirstIssueIssuesCount",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v19/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v25/*: any*/),
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
                              (v10/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v11/*: any*/),
                                  (v23/*: any*/),
                                  (v17/*: any*/),
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
                                      (v11/*: any*/),
                                      (v13/*: any*/),
                                      (v26/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v34/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v27/*: any*/),
                                          (v20/*: any*/),
                                          (v28/*: any*/),
                                          (v29/*: any*/),
                                          (v30/*: any*/),
                                          (v31/*: any*/),
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "reviewDecision",
                                            "storageKey": null
                                          },
                                          (v35/*: any*/),
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "isInMergeQueue",
                                            "storageKey": null
                                          },
                                          (v36/*: any*/),
                                          (v33/*: any*/)
                                        ],
                                        "type": "PullRequest",
                                        "abstractKey": null
                                      }
                                    ],
                                    "type": "IssueOrPullRequest",
                                    "abstractKey": "__isIssueOrPullRequest"
                                  }
                                ],
                                "type": "Issue",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v11/*: any*/),
                                  (v23/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": [
                                      (v13/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": null,
                                        "kind": "LinkedField",
                                        "name": "owner",
                                        "plural": false,
                                        "selections": [
                                          (v10/*: any*/),
                                          (v12/*: any*/),
                                          (v11/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v11/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v17/*: any*/),
                                  (v18/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v34/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v27/*: any*/),
                                          (v20/*: any*/),
                                          (v28/*: any*/),
                                          (v29/*: any*/),
                                          (v30/*: any*/),
                                          (v31/*: any*/),
                                          (v35/*: any*/),
                                          (v36/*: any*/),
                                          (v33/*: any*/)
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
                                  (v11/*: any*/)
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
                "args": (v25/*: any*/),
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
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "safeViewer",
        "plural": false,
        "selections": [
          (v11/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v10/*: any*/),
              (v12/*: any*/),
              (v13/*: any*/),
              (v14/*: any*/),
              (v15/*: any*/),
              (v16/*: any*/)
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
    "id": "eada1d8465212306d51e35765903297b",
    "metadata": {},
    "name": "IssueIndexPageQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b59a0f9f85c49e982e1834713e262af6";

export default node;
