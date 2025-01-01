/**
 * @generated SignedSource<<763159120f57e5466bd8fa27b911939f>>
 * @relayHash 2db11fba32778cb6a311b64375ed7949
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2db11fba32778cb6a311b64375ed7949

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueRowTestQuery$variables = {
  id: string;
};
export type IssueRowTestQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueRow">;
  } | null | undefined;
};
export type IssueRowTestQuery = {
  response: IssueRowTestQuery$data;
  variables: IssueRowTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "first",
      "value": 5
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
        (v3/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        (v6/*: any*/),
        (v5/*: any*/),
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
  "storageKey": "labels(first:5,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
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
  "name": "closed",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v7/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": null
    },
    (v3/*: any*/)
  ],
  "storageKey": null
},
v14 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v4/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "url",
        "storageKey": null
      },
      (v3/*: any*/)
    ],
    "storageKey": null
  }
],
v15 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v14/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v14/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v16 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v17 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v18 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v19 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueRowTestQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
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
                  {
                    "kind": "Literal",
                    "name": "fetchRepository",
                    "value": true
                  },
                  {
                    "kind": "Literal",
                    "name": "labelPageSize",
                    "value": 5
                  }
                ],
                "kind": "FragmentSpread",
                "name": "IssueRow"
              }
            ],
            "type": "Issue",
            "abstractKey": null
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssueRowTestQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v4/*: any*/),
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
                  (v3/*: any*/),
                  (v5/*: any*/),
                  (v6/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "number",
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
                  (v5/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v7/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v8/*: any*/),
                      (v9/*: any*/),
                      (v10/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      (v13/*: any*/),
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
                      (v15/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v8/*: any*/),
                      (v9/*: any*/),
                      (v10/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      (v13/*: any*/),
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
                      },
                      (v15/*: any*/)
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
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "2db11fba32778cb6a311b64375ed7949",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "issue.__isIssueOrPullRequest": (v16/*: any*/),
        "issue.__typename": (v16/*: any*/),
        "issue.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "issue.author.__typename": (v16/*: any*/),
        "issue.author.avatarUrl": (v17/*: any*/),
        "issue.author.id": (v18/*: any*/),
        "issue.author.login": (v16/*: any*/),
        "issue.closed": (v19/*: any*/),
        "issue.closedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "issue.createdAt": (v20/*: any*/),
        "issue.id": (v18/*: any*/),
        "issue.isDraft": (v19/*: any*/),
        "issue.isInMergeQueue": (v19/*: any*/),
        "issue.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "issue.issueType.color": {
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
        "issue.issueType.id": (v18/*: any*/),
        "issue.issueType.name": (v16/*: any*/),
        "issue.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "issue.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "issue.labels.nodes.color": (v16/*: any*/),
        "issue.labels.nodes.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "issue.labels.nodes.id": (v18/*: any*/),
        "issue.labels.nodes.name": (v16/*: any*/),
        "issue.labels.nodes.nameHTML": (v16/*: any*/),
        "issue.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "issue.milestone.id": (v18/*: any*/),
        "issue.milestone.title": (v16/*: any*/),
        "issue.milestone.url": (v17/*: any*/),
        "issue.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "issue.pullRequestState": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "issue.repository.id": (v18/*: any*/),
        "issue.repository.name": (v16/*: any*/),
        "issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issue.repository.owner.__typename": (v16/*: any*/),
        "issue.repository.owner.id": (v18/*: any*/),
        "issue.repository.owner.login": (v16/*: any*/),
        "issue.reviewDecision": {
          "enumValues": [
            "APPROVED",
            "CHANGES_REQUESTED",
            "REVIEW_REQUIRED"
          ],
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewDecision"
        },
        "issue.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "issue.stateReason": {
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
        "issue.title": (v16/*: any*/),
        "issue.titleHtml": (v16/*: any*/),
        "issue.updatedAt": (v20/*: any*/)
      }
    },
    "name": "IssueRowTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "5b5ac50db982d57e320157c2bc4d3acf";

export default node;
