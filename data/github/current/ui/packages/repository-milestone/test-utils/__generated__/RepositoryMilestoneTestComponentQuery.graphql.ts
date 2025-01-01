/**
 * @generated SignedSource<<03a19c51650a5483924c577abe11f93f>>
 * @relayHash d012b7d6ec645ac9eeda3e82bb9a3109
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d012b7d6ec645ac9eeda3e82bb9a3109

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestoneTestComponentQuery$variables = Record<PropertyKey, never>;
export type RepositoryMilestoneTestComponentQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneInternal">;
  } | null | undefined;
};
export type RepositoryMilestoneTestComponentQuery = {
  response: RepositoryMilestoneTestComponentQuery$data;
  variables: RepositoryMilestoneTestComponentQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "mockRepoId1"
  }
],
v1 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v2 = {
  "kind": "Literal",
  "name": "number",
  "value": 1
},
v3 = {
  "kind": "Literal",
  "name": "query",
  "value": ""
},
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
  "name": "id",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
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
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v4/*: any*/),
    (v12/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v15 = [
  {
    "kind": "Literal",
    "name": "aggregations",
    "value": true
  },
  (v1/*: any*/),
  (v3/*: any*/),
  {
    "kind": "Literal",
    "name": "type",
    "value": "ISSUE_ADVANCED"
  }
],
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": [
    (v1/*: any*/),
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
        (v5/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        (v16/*: any*/),
        (v14/*: any*/),
        (v11/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "labels(first:10,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
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
  "name": "closedAt",
  "storageKey": null
},
v20 = {
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
    (v4/*: any*/),
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
    (v5/*: any*/)
  ],
  "storageKey": null
},
v21 = {
  "kind": "InlineFragment",
  "selections": [
    (v17/*: any*/),
    (v18/*: any*/),
    (v10/*: any*/),
    (v7/*: any*/),
    (v19/*: any*/),
    (v20/*: any*/),
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
    }
  ],
  "type": "Issue",
  "abstractKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v23 = {
  "alias": "pullRequestState",
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v25 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v27 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v28 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v29 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "RepositoryMilestoneTestComponentQuery",
    "selections": [
      {
        "alias": "repository",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": [
                  (v1/*: any*/),
                  (v2/*: any*/),
                  (v3/*: any*/)
                ],
                "kind": "FragmentSpread",
                "name": "RepositoryMilestoneInternal"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"mockRepoId1\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "RepositoryMilestoneTestComponentQuery",
    "selections": [
      {
        "alias": "repository",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          (v5/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v6/*: any*/),
              {
                "alias": null,
                "args": [
                  (v2/*: any*/)
                ],
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": [
                  (v5/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "repository",
                    "plural": false,
                    "selections": [
                      (v6/*: any*/),
                      (v5/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  (v10/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "openIssueCount",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "closedIssueCount",
                    "storageKey": null
                  },
                  (v11/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "descriptionHTML",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "progressPercentage",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "dueOn",
                    "storageKey": null
                  }
                ],
                "storageKey": "milestone(number:1)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanPush",
                "storageKey": null
              },
              (v13/*: any*/),
              (v14/*: any*/),
              {
                "alias": null,
                "args": (v15/*: any*/),
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
                          (v4/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v5/*: any*/),
                              (v9/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "state",
                                "storageKey": null
                              },
                              (v8/*: any*/),
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
                                  (v5/*: any*/),
                                  (v14/*: any*/),
                                  (v16/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v21/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v17/*: any*/),
                                      (v18/*: any*/),
                                      (v10/*: any*/),
                                      (v7/*: any*/),
                                      (v19/*: any*/),
                                      (v20/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "reviewDecision",
                                        "storageKey": null
                                      },
                                      (v22/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "isInMergeQueue",
                                        "storageKey": null
                                      },
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
                              (v5/*: any*/),
                              (v9/*: any*/),
                              (v7/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "repository",
                                "plural": false,
                                "selections": [
                                  (v14/*: any*/),
                                  (v13/*: any*/),
                                  (v5/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v8/*: any*/),
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
                                  (v21/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v17/*: any*/),
                                      (v18/*: any*/),
                                      (v10/*: any*/),
                                      (v19/*: any*/),
                                      (v20/*: any*/),
                                      (v22/*: any*/),
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
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v5/*: any*/)
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
                "storageKey": "search(aggregations:true,first:10,query:\"\",type:\"ISSUE_ADVANCED\")"
              },
              {
                "alias": null,
                "args": (v15/*: any*/),
                "filters": [
                  "query",
                  "type",
                  "aggregations"
                ],
                "handle": "connection",
                "key": "MilestoneIssuesList_search",
                "kind": "LinkedHandle",
                "name": "search"
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
                "name": "isInOrganization",
                "storageKey": null
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"mockRepoId1\")"
      }
    ]
  },
  "params": {
    "id": "d012b7d6ec645ac9eeda3e82bb9a3109",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "repository.__typename": (v24/*: any*/),
        "repository.id": (v25/*: any*/),
        "repository.isArchived": (v26/*: any*/),
        "repository.isDisabled": (v26/*: any*/),
        "repository.isInOrganization": (v26/*: any*/),
        "repository.isLocked": (v26/*: any*/),
        "repository.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "repository.milestone.closed": (v26/*: any*/),
        "repository.milestone.closedIssueCount": (v27/*: any*/),
        "repository.milestone.description": (v28/*: any*/),
        "repository.milestone.descriptionHTML": (v28/*: any*/),
        "repository.milestone.dueOn": (v29/*: any*/),
        "repository.milestone.id": (v25/*: any*/),
        "repository.milestone.number": (v27/*: any*/),
        "repository.milestone.openIssueCount": (v27/*: any*/),
        "repository.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "repository.milestone.repository": (v30/*: any*/),
        "repository.milestone.repository.id": (v25/*: any*/),
        "repository.milestone.repository.nameWithOwner": (v24/*: any*/),
        "repository.milestone.title": (v24/*: any*/),
        "repository.milestone.updatedAt": (v31/*: any*/),
        "repository.name": (v24/*: any*/),
        "repository.nameWithOwner": (v24/*: any*/),
        "repository.owner": (v32/*: any*/),
        "repository.owner.__typename": (v24/*: any*/),
        "repository.owner.id": (v25/*: any*/),
        "repository.owner.login": (v24/*: any*/),
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
        "repository.search.edges.cursor": (v24/*: any*/),
        "repository.search.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "SearchResultItem"
        },
        "repository.search.edges.node.__isIssueOrPullRequest": (v24/*: any*/),
        "repository.search.edges.node.__isNode": (v24/*: any*/),
        "repository.search.edges.node.__typename": (v24/*: any*/),
        "repository.search.edges.node.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "repository.search.edges.node.author.__typename": (v24/*: any*/),
        "repository.search.edges.node.author.id": (v25/*: any*/),
        "repository.search.edges.node.author.isCopilot": (v26/*: any*/),
        "repository.search.edges.node.author.login": (v24/*: any*/),
        "repository.search.edges.node.author.resourcePath": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "repository.search.edges.node.closed": (v26/*: any*/),
        "repository.search.edges.node.closedAt": (v29/*: any*/),
        "repository.search.edges.node.createdAt": (v31/*: any*/),
        "repository.search.edges.node.id": (v25/*: any*/),
        "repository.search.edges.node.isDraft": (v26/*: any*/),
        "repository.search.edges.node.isInMergeQueue": (v26/*: any*/),
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
        "repository.search.edges.node.issueType.id": (v25/*: any*/),
        "repository.search.edges.node.issueType.name": (v24/*: any*/),
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
        "repository.search.edges.node.labels.nodes.color": (v24/*: any*/),
        "repository.search.edges.node.labels.nodes.description": (v28/*: any*/),
        "repository.search.edges.node.labels.nodes.id": (v25/*: any*/),
        "repository.search.edges.node.labels.nodes.name": (v24/*: any*/),
        "repository.search.edges.node.labels.nodes.nameHTML": (v24/*: any*/),
        "repository.search.edges.node.number": (v27/*: any*/),
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
        "repository.search.edges.node.repository": (v30/*: any*/),
        "repository.search.edges.node.repository.id": (v25/*: any*/),
        "repository.search.edges.node.repository.name": (v24/*: any*/),
        "repository.search.edges.node.repository.owner": (v32/*: any*/),
        "repository.search.edges.node.repository.owner.__typename": (v24/*: any*/),
        "repository.search.edges.node.repository.owner.id": (v25/*: any*/),
        "repository.search.edges.node.repository.owner.login": (v24/*: any*/),
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
        "repository.search.edges.node.title": (v24/*: any*/),
        "repository.search.edges.node.titleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "repository.search.edges.node.titleHtml": (v24/*: any*/),
        "repository.search.edges.node.updatedAt": (v31/*: any*/),
        "repository.search.issueCount": (v27/*: any*/),
        "repository.search.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "repository.search.pageInfo.endCursor": (v28/*: any*/),
        "repository.search.pageInfo.hasNextPage": (v26/*: any*/),
        "repository.viewerCanPush": (v26/*: any*/)
      }
    },
    "name": "RepositoryMilestoneTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "28cf11f577eb50b1ccb605d0bd4b9599";

export default node;
