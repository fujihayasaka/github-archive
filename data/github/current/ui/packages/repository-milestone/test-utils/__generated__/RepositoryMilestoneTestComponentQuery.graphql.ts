/**
 * @generated SignedSource<<cb2842c66b8ef24680c14b9dc08eddb3>>
 * @relayHash 94f0bfbe2468a74acf4a8570e88ac404
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 94f0bfbe2468a74acf4a8570e88ac404

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestoneTestComponentQuery$variables = Record<PropertyKey, never>;
export type RepositoryMilestoneTestComponentQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestone">;
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
  "name": "states",
  "value": [
    "OPEN"
  ]
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
  "name": "title",
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
  "name": "updatedAt",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v12 = {
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
        (v11/*: any*/),
        (v10/*: any*/),
        (v9/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "labels(first:10,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    },
    (v4/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v16 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v17 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
],
v18 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v19 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v23 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v24 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v25 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
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
                "name": "RepositoryMilestone"
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
                  (v6/*: any*/),
                  (v7/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "dueOn",
                    "storageKey": null
                  },
                  (v8/*: any*/),
                  (v9/*: any*/),
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
                    "args": [
                      (v1/*: any*/),
                      (v3/*: any*/)
                    ],
                    "concreteType": "IssueConnection",
                    "kind": "LinkedField",
                    "name": "issues",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "IssueEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Issue",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              (v5/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "number",
                                "storageKey": null
                              },
                              (v4/*: any*/),
                              (v6/*: any*/),
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
                                  (v10/*: any*/),
                                  (v11/*: any*/)
                                ],
                                "storageKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v12/*: any*/),
                                      (v13/*: any*/),
                                      (v8/*: any*/),
                                      (v7/*: any*/),
                                      (v14/*: any*/),
                                      (v15/*: any*/),
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
                                      }
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v12/*: any*/),
                                      (v13/*: any*/),
                                      (v8/*: any*/),
                                      (v7/*: any*/),
                                      (v14/*: any*/),
                                      (v15/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "reviewDecision",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "isDraft",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "isInMergeQueue",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": "pullRequestState",
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "state",
                                        "storageKey": null
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
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "issues(first:10,states:[\"OPEN\"])"
                  },
                  {
                    "alias": "closedIssues",
                    "args": [
                      (v16/*: any*/),
                      {
                        "kind": "Literal",
                        "name": "states",
                        "value": "CLOSED"
                      }
                    ],
                    "concreteType": "IssueConnection",
                    "kind": "LinkedField",
                    "name": "issues",
                    "plural": false,
                    "selections": (v17/*: any*/),
                    "storageKey": "issues(first:0,states:\"CLOSED\")"
                  },
                  {
                    "alias": "openIssues",
                    "args": [
                      (v16/*: any*/),
                      {
                        "kind": "Literal",
                        "name": "states",
                        "value": "OPEN"
                      }
                    ],
                    "concreteType": "IssueConnection",
                    "kind": "LinkedField",
                    "name": "issues",
                    "plural": false,
                    "selections": (v17/*: any*/),
                    "storageKey": "issues(first:0,states:\"OPEN\")"
                  },
                  (v5/*: any*/)
                ],
                "storageKey": "milestone(number:1)"
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
    "id": "94f0bfbe2468a74acf4a8570e88ac404",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "repository.__typename": (v18/*: any*/),
        "repository.id": (v19/*: any*/),
        "repository.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "repository.milestone.closed": (v20/*: any*/),
        "repository.milestone.closedIssues": (v21/*: any*/),
        "repository.milestone.closedIssues.totalCount": (v22/*: any*/),
        "repository.milestone.description": (v23/*: any*/),
        "repository.milestone.descriptionHTML": (v23/*: any*/),
        "repository.milestone.dueOn": (v24/*: any*/),
        "repository.milestone.id": (v19/*: any*/),
        "repository.milestone.issues": (v21/*: any*/),
        "repository.milestone.issues.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueEdge"
        },
        "repository.milestone.issues.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.milestone.issues.edges.node.__isIssueOrPullRequest": (v18/*: any*/),
        "repository.milestone.issues.edges.node.__typename": (v18/*: any*/),
        "repository.milestone.issues.edges.node.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "repository.milestone.issues.edges.node.author.__typename": (v18/*: any*/),
        "repository.milestone.issues.edges.node.author.id": (v19/*: any*/),
        "repository.milestone.issues.edges.node.author.login": (v18/*: any*/),
        "repository.milestone.issues.edges.node.closed": (v20/*: any*/),
        "repository.milestone.issues.edges.node.closedAt": (v24/*: any*/),
        "repository.milestone.issues.edges.node.createdAt": (v25/*: any*/),
        "repository.milestone.issues.edges.node.id": (v19/*: any*/),
        "repository.milestone.issues.edges.node.isDraft": (v20/*: any*/),
        "repository.milestone.issues.edges.node.isInMergeQueue": (v20/*: any*/),
        "repository.milestone.issues.edges.node.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "repository.milestone.issues.edges.node.issueType.color": {
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
        "repository.milestone.issues.edges.node.issueType.id": (v19/*: any*/),
        "repository.milestone.issues.edges.node.issueType.name": (v18/*: any*/),
        "repository.milestone.issues.edges.node.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "repository.milestone.issues.edges.node.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "repository.milestone.issues.edges.node.labels.nodes.color": (v18/*: any*/),
        "repository.milestone.issues.edges.node.labels.nodes.description": (v23/*: any*/),
        "repository.milestone.issues.edges.node.labels.nodes.id": (v19/*: any*/),
        "repository.milestone.issues.edges.node.labels.nodes.name": (v18/*: any*/),
        "repository.milestone.issues.edges.node.labels.nodes.nameHTML": (v18/*: any*/),
        "repository.milestone.issues.edges.node.number": (v22/*: any*/),
        "repository.milestone.issues.edges.node.pullRequestState": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "repository.milestone.issues.edges.node.reviewDecision": {
          "enumValues": [
            "APPROVED",
            "CHANGES_REQUESTED",
            "REVIEW_REQUIRED"
          ],
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewDecision"
        },
        "repository.milestone.issues.edges.node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "repository.milestone.issues.edges.node.stateReason": {
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
        "repository.milestone.issues.edges.node.title": (v18/*: any*/),
        "repository.milestone.issues.edges.node.titleHtml": (v18/*: any*/),
        "repository.milestone.issues.edges.node.updatedAt": (v25/*: any*/),
        "repository.milestone.openIssues": (v21/*: any*/),
        "repository.milestone.openIssues.totalCount": (v22/*: any*/),
        "repository.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "repository.milestone.title": (v18/*: any*/),
        "repository.milestone.updatedAt": (v25/*: any*/)
      }
    },
    "name": "RepositoryMilestoneTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "9ff78448c5c4c42fc7ff036561c888d3";

export default node;
