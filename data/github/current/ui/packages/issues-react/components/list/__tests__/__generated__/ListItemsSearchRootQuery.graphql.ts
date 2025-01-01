/**
 * @generated SignedSource<<2880a2acf4a6f693854957d381f90ae7>>
 * @relayHash 35dd6204ce8d1ea590f40079ca3d502c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 35dd6204ce8d1ea590f40079ca3d502c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListItemsSearchRootQuery$variables = {
  first?: number | null | undefined;
  includeGitData?: boolean | null | undefined;
  query: string;
  skip?: number | null | undefined;
};
export type ListItemsSearchRootQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"ListItemsPaginated_results">;
  } | null | undefined;
};
export type ListItemsSearchRootQuery = {
  response: ListItemsSearchRootQuery$data;
  variables: ListItemsSearchRootQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": 25,
  "kind": "LocalArgument",
  "name": "first"
},
v1 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "includeGitData"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "query"
},
v3 = {
  "defaultValue": 0,
  "kind": "LocalArgument",
  "name": "skip"
},
v4 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "hyperlist-web"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "github"
  }
],
v5 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v6 = {
  "kind": "Variable",
  "name": "query",
  "variableName": "query"
},
v7 = {
  "kind": "Variable",
  "name": "skip",
  "variableName": "skip"
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v9 = [
  (v5/*: any*/),
  (v6/*: any*/),
  (v7/*: any*/),
  {
    "kind": "Literal",
    "name": "type",
    "value": "ISSUE_ADVANCED"
  }
],
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
  "name": "number",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
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
  "name": "color",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v16 = {
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
        (v15/*: any*/),
        (v8/*: any*/)
      ],
      "storageKey": null
    },
    (v8/*: any*/)
  ],
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "first",
      "value": 20
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
        (v8/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        (v14/*: any*/),
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
  "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "resourcePath",
      "storageKey": null
    },
    (v10/*: any*/),
    {
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
    (v8/*: any*/)
  ],
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v24 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v12/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "url",
        "storageKey": null
      },
      (v8/*: any*/)
    ],
    "storageKey": null
  }
],
v25 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v24/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v24/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v26 = {
  "kind": "InlineFragment",
  "selections": [
    (v17/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/),
    (v20/*: any*/),
    (v21/*: any*/),
    (v22/*: any*/),
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
    (v23/*: any*/),
    (v25/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "reviewDecision",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v30 = {
  "alias": "pullRequestState",
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "concreteType": "StatusCheckRollup",
  "kind": "LinkedField",
  "name": "statusCheckRollup",
  "plural": false,
  "selections": [
    (v23/*: any*/),
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
            (v23/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v8/*: any*/)
  ],
  "storageKey": null
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v36 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v37 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "StatusCheckRollup"
},
v38 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "StatusCheckRollupContextConnection"
},
v39 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v40 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "CheckRunStateCount"
},
v41 = {
  "enumValues": [
    "ACTION_REQUIRED",
    "CANCELLED",
    "COMPLETED",
    "FAILURE",
    "IN_PROGRESS",
    "NEUTRAL",
    "PENDING",
    "QUEUED",
    "SKIPPED",
    "STALE",
    "STARTUP_FAILURE",
    "SUCCESS",
    "TIMED_OUT",
    "WAITING"
  ],
  "nullable": false,
  "plural": false,
  "type": "CheckRunState"
},
v42 = {
  "enumValues": [
    "ERROR",
    "EXPECTED",
    "FAILURE",
    "PENDING",
    "SUCCESS"
  ],
  "nullable": false,
  "plural": false,
  "type": "StatusState"
},
v43 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "ListItemsSearchRootQuery",
    "selections": [
      {
        "alias": null,
        "args": (v4/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Literal",
                "name": "fetchRepository",
                "value": true
              },
              (v5/*: any*/),
              {
                "kind": "Variable",
                "name": "includeGitData",
                "variableName": "includeGitData"
              },
              {
                "kind": "Literal",
                "name": "labelPageSize",
                "value": 20
              },
              (v6/*: any*/),
              (v7/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "ListItemsPaginated_results"
          }
        ],
        "storageKey": "repository(name:\"hyperlist-web\",owner:\"github\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v2/*: any*/),
      (v0/*: any*/),
      (v3/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "ListItemsSearchRootQuery",
    "selections": [
      {
        "alias": null,
        "args": (v4/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v8/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v9/*: any*/),
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
                                  (v8/*: any*/),
                                  (v11/*: any*/),
                                  (v12/*: any*/),
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
                                      (v8/*: any*/),
                                      (v13/*: any*/),
                                      (v14/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v16/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v26/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v17/*: any*/),
                                          (v18/*: any*/),
                                          (v19/*: any*/),
                                          (v20/*: any*/),
                                          (v21/*: any*/),
                                          (v22/*: any*/),
                                          (v27/*: any*/),
                                          (v28/*: any*/),
                                          (v29/*: any*/),
                                          (v30/*: any*/),
                                          (v25/*: any*/)
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
                                  (v8/*: any*/),
                                  (v11/*: any*/),
                                  (v16/*: any*/),
                                  (v12/*: any*/),
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
                                              (v8/*: any*/),
                                              (v31/*: any*/)
                                            ],
                                            "storageKey": null
                                          },
                                          (v8/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v31/*: any*/)
                                    ]
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v26/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v17/*: any*/),
                                          (v18/*: any*/),
                                          (v19/*: any*/),
                                          (v20/*: any*/),
                                          (v21/*: any*/),
                                          (v22/*: any*/),
                                          (v28/*: any*/),
                                          (v30/*: any*/),
                                          (v25/*: any*/),
                                          {
                                            "condition": "includeGitData",
                                            "kind": "Condition",
                                            "passingValue": true,
                                            "selections": [
                                              (v27/*: any*/),
                                              (v29/*: any*/)
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
                                  (v8/*: any*/)
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
                "args": (v9/*: any*/),
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
        "storageKey": "repository(name:\"hyperlist-web\",owner:\"github\")"
      }
    ]
  },
  "params": {
    "id": "35dd6204ce8d1ea590f40079ca3d502c",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.__isNode": (v32/*: any*/),
        "repository.__isSearchable": (v32/*: any*/),
        "repository.id": (v33/*: any*/),
        "repository.search": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SearchResultItemConnection"
        },
        "repository.search.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "SearchResultItemEdge"
        },
        "repository.search.edges.cursor": (v32/*: any*/),
        "repository.search.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "SearchResultItem"
        },
        "repository.search.edges.node.__isIssueOrPullRequest": (v32/*: any*/),
        "repository.search.edges.node.__isNode": (v32/*: any*/),
        "repository.search.edges.node.__typename": (v32/*: any*/),
        "repository.search.edges.node.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "repository.search.edges.node.author.__typename": (v32/*: any*/),
        "repository.search.edges.node.author.id": (v33/*: any*/),
        "repository.search.edges.node.author.isCopilot": (v34/*: any*/),
        "repository.search.edges.node.author.login": (v32/*: any*/),
        "repository.search.edges.node.author.resourcePath": (v35/*: any*/),
        "repository.search.edges.node.closed": (v34/*: any*/),
        "repository.search.edges.node.closedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "repository.search.edges.node.createdAt": (v36/*: any*/),
        "repository.search.edges.node.headCommit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestCommit"
        },
        "repository.search.edges.node.headCommit.commit": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Commit"
        },
        "repository.search.edges.node.headCommit.commit.id": (v33/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup": (v37/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.contexts": (v38/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCount": (v39/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState": (v40/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState.count": (v39/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState.state": (v41/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.id": (v33/*: any*/),
        "repository.search.edges.node.headCommit.commit.statusCheckRollup.state": (v42/*: any*/),
        "repository.search.edges.node.headCommit.id": (v33/*: any*/),
        "repository.search.edges.node.id": (v33/*: any*/),
        "repository.search.edges.node.isDraft": (v34/*: any*/),
        "repository.search.edges.node.isInMergeQueue": (v34/*: any*/),
        "repository.search.edges.node.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "repository.search.edges.node.issueType.color": {
          "enumValues": [
            "BLUE",
            "GRAY",
            "GREEN",
            "ORANGE",
            "PINK",
            "PURPLE",
            "RED",
            "YELLOW"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueTypeColor"
        },
        "repository.search.edges.node.issueType.id": (v33/*: any*/),
        "repository.search.edges.node.issueType.name": (v32/*: any*/),
        "repository.search.edges.node.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "repository.search.edges.node.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "repository.search.edges.node.labels.nodes.color": (v32/*: any*/),
        "repository.search.edges.node.labels.nodes.description": (v43/*: any*/),
        "repository.search.edges.node.labels.nodes.id": (v33/*: any*/),
        "repository.search.edges.node.labels.nodes.name": (v32/*: any*/),
        "repository.search.edges.node.labels.nodes.nameHTML": (v32/*: any*/),
        "repository.search.edges.node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "repository.search.edges.node.milestone.id": (v33/*: any*/),
        "repository.search.edges.node.milestone.title": (v32/*: any*/),
        "repository.search.edges.node.milestone.url": (v35/*: any*/),
        "repository.search.edges.node.number": (v39/*: any*/),
        "repository.search.edges.node.pullRequestState": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "repository.search.edges.node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "repository.search.edges.node.repository.id": (v33/*: any*/),
        "repository.search.edges.node.repository.name": (v32/*: any*/),
        "repository.search.edges.node.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.search.edges.node.repository.owner.__typename": (v32/*: any*/),
        "repository.search.edges.node.repository.owner.id": (v33/*: any*/),
        "repository.search.edges.node.repository.owner.login": (v32/*: any*/),
        "repository.search.edges.node.reviewDecision": {
          "enumValues": [
            "APPROVED",
            "CHANGES_REQUESTED",
            "REVIEW_REQUIRED"
          ],
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewDecision"
        },
        "repository.search.edges.node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "repository.search.edges.node.stateReason": {
          "enumValues": [
            "COMPLETED",
            "DUPLICATE",
            "NOT_PLANNED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": false,
          "type": "IssueStateReason"
        },
        "repository.search.edges.node.statusCheckRollup": (v37/*: any*/),
        "repository.search.edges.node.statusCheckRollup.contexts": (v38/*: any*/),
        "repository.search.edges.node.statusCheckRollup.contexts.checkRunCount": (v39/*: any*/),
        "repository.search.edges.node.statusCheckRollup.contexts.checkRunCountsByState": (v40/*: any*/),
        "repository.search.edges.node.statusCheckRollup.contexts.checkRunCountsByState.count": (v39/*: any*/),
        "repository.search.edges.node.statusCheckRollup.contexts.checkRunCountsByState.state": (v41/*: any*/),
        "repository.search.edges.node.statusCheckRollup.id": (v33/*: any*/),
        "repository.search.edges.node.statusCheckRollup.state": (v42/*: any*/),
        "repository.search.edges.node.title": (v32/*: any*/),
        "repository.search.edges.node.titleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "repository.search.edges.node.titleHtml": (v32/*: any*/),
        "repository.search.edges.node.updatedAt": (v36/*: any*/),
        "repository.search.issueCount": (v39/*: any*/),
        "repository.search.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "repository.search.pageInfo.endCursor": (v43/*: any*/),
        "repository.search.pageInfo.hasNextPage": (v34/*: any*/),
        "repository.search.pageInfo.hasPreviousPage": (v34/*: any*/),
        "repository.search.pageInfo.startCursor": (v43/*: any*/)
      }
    },
    "name": "ListItemsSearchRootQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "97e4c6c0960e127fb9a022624e9b7df1";

export default node;
