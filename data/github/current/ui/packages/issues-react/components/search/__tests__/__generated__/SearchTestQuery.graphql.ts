/**
 * @generated SignedSource<<1f9c25e56f19cefb3ec38700baf36ff7>>
 * @relayHash fcd18ec40a4b6adc75d9ab18451b36b0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fcd18ec40a4b6adc75d9ab18451b36b0

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SearchTestQuery$variables = {
  first?: number | null | undefined;
  labelPageSize?: number | null | undefined;
  query?: string | null | undefined;
  skip?: number | null | undefined;
};
export type SearchTestQuery$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchRootFragment">;
};
export type SearchTestQuery = {
  response: SearchTestQuery$data;
  variables: SearchTestQuery$variables;
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
  "defaultValue": "state:open archived:false assignee:@me sort:updated-desc",
  "kind": "LocalArgument",
  "name": "query"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "skip"
},
v4 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v5 = {
  "kind": "Variable",
  "name": "query",
  "variableName": "query"
},
v6 = {
  "kind": "Variable",
  "name": "skip",
  "variableName": "skip"
},
v7 = [
  (v4/*: any*/),
  (v5/*: any*/),
  (v6/*: any*/),
  {
    "kind": "Literal",
    "name": "type",
    "value": "ISSUE_ADVANCED"
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
  "name": "number",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        (v8/*: any*/),
        (v14/*: any*/),
        (v9/*: any*/)
      ],
      "storageKey": null
    },
    (v9/*: any*/)
  ],
  "storageKey": null
},
v16 = {
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
        (v9/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        (v13/*: any*/),
        (v12/*: any*/),
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
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v14/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": null
    },
    (v9/*: any*/)
  ],
  "storageKey": null
},
v22 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v11/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "url",
        "storageKey": null
      },
      (v9/*: any*/)
    ],
    "storageKey": null
  }
],
v23 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v22/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v22/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v24 = {
  "kind": "InlineFragment",
  "selections": [
    (v16/*: any*/),
    (v17/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/),
    (v20/*: any*/),
    (v21/*: any*/),
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
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "state",
      "storageKey": null
    },
    (v23/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v26 = {
  "alias": "pullRequestState",
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v27 = {
  "kind": "InlineFragment",
  "selections": [
    (v9/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v28 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v33 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
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
    "name": "SearchTestQuery",
    "selections": [
      {
        "args": [
          {
            "kind": "Literal",
            "name": "fetchRepository",
            "value": true
          },
          (v4/*: any*/),
          {
            "kind": "Variable",
            "name": "labelPageSize",
            "variableName": "labelPageSize"
          },
          (v5/*: any*/),
          (v6/*: any*/)
        ],
        "kind": "FragmentSpread",
        "name": "SearchRootFragment"
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
      (v1/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Operation",
    "name": "SearchTestQuery",
    "selections": [
      {
        "kind": "InlineFragment",
        "selections": [
          {
            "alias": null,
            "args": (v7/*: any*/),
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
                          (v8/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v9/*: any*/),
                              (v10/*: any*/),
                              (v11/*: any*/),
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
                                  (v9/*: any*/),
                                  (v12/*: any*/),
                                  (v13/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v15/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v24/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v16/*: any*/),
                                      (v17/*: any*/),
                                      (v18/*: any*/),
                                      (v19/*: any*/),
                                      (v20/*: any*/),
                                      (v21/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "reviewDecision",
                                        "storageKey": null
                                      },
                                      (v25/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "isInMergeQueue",
                                        "storageKey": null
                                      },
                                      (v26/*: any*/),
                                      (v23/*: any*/)
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
                              (v9/*: any*/),
                              (v10/*: any*/),
                              (v15/*: any*/),
                              (v11/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "titleHTML",
                                "storageKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v24/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v16/*: any*/),
                                      (v17/*: any*/),
                                      (v18/*: any*/),
                                      (v19/*: any*/),
                                      (v20/*: any*/),
                                      (v21/*: any*/),
                                      (v25/*: any*/),
                                      (v26/*: any*/),
                                      (v23/*: any*/)
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
                          (v27/*: any*/)
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
            "args": (v7/*: any*/),
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
          (v27/*: any*/)
        ],
        "type": "Searchable",
        "abstractKey": "__isSearchable"
      }
    ]
  },
  "params": {
    "id": "fcd18ec40a4b6adc75d9ab18451b36b0",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "__isNode": (v28/*: any*/),
        "__isSearchable": (v28/*: any*/),
        "id": (v29/*: any*/),
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
        "search.edges.cursor": (v28/*: any*/),
        "search.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "SearchResultItem"
        },
        "search.edges.node.__isIssueOrPullRequest": (v28/*: any*/),
        "search.edges.node.__isNode": (v28/*: any*/),
        "search.edges.node.__typename": (v28/*: any*/),
        "search.edges.node.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "search.edges.node.author.__typename": (v28/*: any*/),
        "search.edges.node.author.avatarUrl": (v30/*: any*/),
        "search.edges.node.author.id": (v29/*: any*/),
        "search.edges.node.author.login": (v28/*: any*/),
        "search.edges.node.closed": (v31/*: any*/),
        "search.edges.node.closedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "search.edges.node.createdAt": (v32/*: any*/),
        "search.edges.node.id": (v29/*: any*/),
        "search.edges.node.isDraft": (v31/*: any*/),
        "search.edges.node.isInMergeQueue": (v31/*: any*/),
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
        "search.edges.node.issueType.id": (v29/*: any*/),
        "search.edges.node.issueType.name": (v28/*: any*/),
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
        "search.edges.node.labels.nodes.color": (v28/*: any*/),
        "search.edges.node.labels.nodes.description": (v33/*: any*/),
        "search.edges.node.labels.nodes.id": (v29/*: any*/),
        "search.edges.node.labels.nodes.name": (v28/*: any*/),
        "search.edges.node.labels.nodes.nameHTML": (v28/*: any*/),
        "search.edges.node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "search.edges.node.milestone.id": (v29/*: any*/),
        "search.edges.node.milestone.title": (v28/*: any*/),
        "search.edges.node.milestone.url": (v30/*: any*/),
        "search.edges.node.number": (v34/*: any*/),
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
        "search.edges.node.repository.id": (v29/*: any*/),
        "search.edges.node.repository.name": (v28/*: any*/),
        "search.edges.node.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "search.edges.node.repository.owner.__typename": (v28/*: any*/),
        "search.edges.node.repository.owner.id": (v29/*: any*/),
        "search.edges.node.repository.owner.login": (v28/*: any*/),
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
        "search.edges.node.title": (v28/*: any*/),
        "search.edges.node.titleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "search.edges.node.titleHtml": (v28/*: any*/),
        "search.edges.node.updatedAt": (v32/*: any*/),
        "search.issueCount": (v34/*: any*/),
        "search.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "search.pageInfo.endCursor": (v33/*: any*/),
        "search.pageInfo.hasNextPage": (v31/*: any*/),
        "search.pageInfo.hasPreviousPage": (v31/*: any*/),
        "search.pageInfo.startCursor": (v33/*: any*/)
      }
    },
    "name": "SearchTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "94aca5cd1c5f330da987f437852d8bba";

export default node;
