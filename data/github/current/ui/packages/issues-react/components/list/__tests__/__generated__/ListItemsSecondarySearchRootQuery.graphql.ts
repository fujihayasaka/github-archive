/**
 * @generated SignedSource<<fcbc7870438d57209b83fd72c1ebff63>>
 * @relayHash 3bab70bccc94e0d84214ede82ad69e5d
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3bab70bccc94e0d84214ede82ad69e5d

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListItemsSecondarySearchRootQuery$variables = {
  first?: number | null | undefined;
  includeGitData?: boolean | null | undefined;
  labelPageSize?: number | null | undefined;
  query?: string | null | undefined;
  skip?: number | null | undefined;
};
export type ListItemsSecondarySearchRootQuery$data = {
  readonly " $fragmentSpreads": FragmentRefs<"ListItemsPaginated_results">;
};
export type ListItemsSecondarySearchRootQuery = {
  response: ListItemsSecondarySearchRootQuery$data;
  variables: ListItemsSecondarySearchRootQuery$variables;
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
  "defaultValue": 20,
  "kind": "LocalArgument",
  "name": "labelPageSize"
},
v3 = {
  "defaultValue": "state:open archived:false assignee:@me sort:updated-desc",
  "kind": "LocalArgument",
  "name": "query"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "skip"
},
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
v8 = [
  (v5/*: any*/),
  (v6/*: any*/),
  (v7/*: any*/),
  {
    "kind": "Literal",
    "name": "type",
    "value": "ISSUE_ADVANCED"
  }
],
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
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
        (v9/*: any*/),
        (v15/*: any*/),
        (v10/*: any*/)
      ],
      "storageKey": null
    },
    (v10/*: any*/)
  ],
  "storageKey": null
},
v17 = {
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
        (v10/*: any*/),
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
  "storageKey": null
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
    (v9/*: any*/),
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
    (v10/*: any*/)
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
      (v10/*: any*/)
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
    (v10/*: any*/)
  ],
  "storageKey": null
},
v32 = {
  "kind": "InlineFragment",
  "selections": [
    (v10/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v36 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "StatusCheckRollup"
},
v39 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "StatusCheckRollupContextConnection"
},
v40 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v41 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "CheckRunStateCount"
},
v42 = {
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
v43 = {
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
v44 = {
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
      (v3/*: any*/),
      (v4/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "ListItemsSecondarySearchRootQuery",
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
            "kind": "Variable",
            "name": "labelPageSize",
            "variableName": "labelPageSize"
          },
          (v6/*: any*/),
          (v7/*: any*/)
        ],
        "kind": "FragmentSpread",
        "name": "ListItemsPaginated_results"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v3/*: any*/),
      (v0/*: any*/),
      (v2/*: any*/),
      (v4/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "ListItemsSecondarySearchRootQuery",
    "selections": [
      {
        "kind": "InlineFragment",
        "selections": [
          {
            "alias": null,
            "args": (v8/*: any*/),
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
                          (v9/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v10/*: any*/),
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
                                  (v10/*: any*/),
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
                              (v10/*: any*/),
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
                                          (v10/*: any*/),
                                          (v31/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v10/*: any*/)
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
                          (v32/*: any*/)
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
            "args": (v8/*: any*/),
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
          (v32/*: any*/)
        ],
        "type": "Searchable",
        "abstractKey": "__isSearchable"
      }
    ]
  },
  "params": {
    "id": "3bab70bccc94e0d84214ede82ad69e5d",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "__isNode": (v33/*: any*/),
        "__isSearchable": (v33/*: any*/),
        "id": (v34/*: any*/),
        "search": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SearchResultItemConnection"
        },
        "search.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "SearchResultItemEdge"
        },
        "search.edges.cursor": (v33/*: any*/),
        "search.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "SearchResultItem"
        },
        "search.edges.node.__isIssueOrPullRequest": (v33/*: any*/),
        "search.edges.node.__isNode": (v33/*: any*/),
        "search.edges.node.__typename": (v33/*: any*/),
        "search.edges.node.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "search.edges.node.author.__typename": (v33/*: any*/),
        "search.edges.node.author.id": (v34/*: any*/),
        "search.edges.node.author.isCopilot": (v35/*: any*/),
        "search.edges.node.author.login": (v33/*: any*/),
        "search.edges.node.author.resourcePath": (v36/*: any*/),
        "search.edges.node.closed": (v35/*: any*/),
        "search.edges.node.closedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "search.edges.node.createdAt": (v37/*: any*/),
        "search.edges.node.headCommit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestCommit"
        },
        "search.edges.node.headCommit.commit": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Commit"
        },
        "search.edges.node.headCommit.commit.id": (v34/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup": (v38/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.contexts": (v39/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCount": (v40/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState": (v41/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState.count": (v40/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState.state": (v42/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.id": (v34/*: any*/),
        "search.edges.node.headCommit.commit.statusCheckRollup.state": (v43/*: any*/),
        "search.edges.node.headCommit.id": (v34/*: any*/),
        "search.edges.node.id": (v34/*: any*/),
        "search.edges.node.isDraft": (v35/*: any*/),
        "search.edges.node.isInMergeQueue": (v35/*: any*/),
        "search.edges.node.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "search.edges.node.issueType.color": {
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
        "search.edges.node.issueType.id": (v34/*: any*/),
        "search.edges.node.issueType.name": (v33/*: any*/),
        "search.edges.node.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "search.edges.node.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "search.edges.node.labels.nodes.color": (v33/*: any*/),
        "search.edges.node.labels.nodes.description": (v44/*: any*/),
        "search.edges.node.labels.nodes.id": (v34/*: any*/),
        "search.edges.node.labels.nodes.name": (v33/*: any*/),
        "search.edges.node.labels.nodes.nameHTML": (v33/*: any*/),
        "search.edges.node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "search.edges.node.milestone.id": (v34/*: any*/),
        "search.edges.node.milestone.title": (v33/*: any*/),
        "search.edges.node.milestone.url": (v36/*: any*/),
        "search.edges.node.number": (v40/*: any*/),
        "search.edges.node.pullRequestState": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "search.edges.node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "search.edges.node.repository.id": (v34/*: any*/),
        "search.edges.node.repository.name": (v33/*: any*/),
        "search.edges.node.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "search.edges.node.repository.owner.__typename": (v33/*: any*/),
        "search.edges.node.repository.owner.id": (v34/*: any*/),
        "search.edges.node.repository.owner.login": (v33/*: any*/),
        "search.edges.node.reviewDecision": {
          "enumValues": [
            "APPROVED",
            "CHANGES_REQUESTED",
            "REVIEW_REQUIRED"
          ],
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewDecision"
        },
        "search.edges.node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "search.edges.node.stateReason": {
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
        "search.edges.node.statusCheckRollup": (v38/*: any*/),
        "search.edges.node.statusCheckRollup.contexts": (v39/*: any*/),
        "search.edges.node.statusCheckRollup.contexts.checkRunCount": (v40/*: any*/),
        "search.edges.node.statusCheckRollup.contexts.checkRunCountsByState": (v41/*: any*/),
        "search.edges.node.statusCheckRollup.contexts.checkRunCountsByState.count": (v40/*: any*/),
        "search.edges.node.statusCheckRollup.contexts.checkRunCountsByState.state": (v42/*: any*/),
        "search.edges.node.statusCheckRollup.id": (v34/*: any*/),
        "search.edges.node.statusCheckRollup.state": (v43/*: any*/),
        "search.edges.node.title": (v33/*: any*/),
        "search.edges.node.titleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "search.edges.node.titleHtml": (v33/*: any*/),
        "search.edges.node.updatedAt": (v37/*: any*/),
        "search.issueCount": (v40/*: any*/),
        "search.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "search.pageInfo.endCursor": (v44/*: any*/),
        "search.pageInfo.hasNextPage": (v35/*: any*/),
        "search.pageInfo.hasPreviousPage": (v35/*: any*/),
        "search.pageInfo.startCursor": (v44/*: any*/)
      }
    },
    "name": "ListItemsSecondarySearchRootQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "623d01e1538ed08d46ad945a5c50637f";

export default node;
