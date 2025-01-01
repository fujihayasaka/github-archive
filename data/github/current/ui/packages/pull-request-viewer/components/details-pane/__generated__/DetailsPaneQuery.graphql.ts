/**
 * @generated SignedSource<<62147923c36bfd78cf23a29b90e14fad>>
 * @relayHash c8055681c0c3e5712b04389d3a2d0d54
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c8055681c0c3e5712b04389d3a2d0d54

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type DetailsPaneQuery$variables = {
  number: number;
  owner: string;
  repo: string;
};
export type DetailsPaneQuery$data = {
  readonly repository: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
    readonly pullRequest: {
      readonly number: number;
      readonly " $fragmentSpreads": FragmentRefs<"DetailsPane_pullRequest">;
    } | null | undefined;
  } | null | undefined;
};
export type DetailsPaneQuery = {
  response: DetailsPaneQuery$data;
  variables: DetailsPaneQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v6 = [
  (v5/*: any*/)
],
v7 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
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
v11 = [
  (v9/*: any*/),
  (v5/*: any*/),
  (v10/*: any*/)
],
v12 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v11/*: any*/),
  "storageKey": null
},
v13 = {
  "kind": "Literal",
  "name": "first",
  "value": 100
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "asCodeOwner",
  "storageKey": null
},
v15 = {
  "kind": "InlineFragment",
  "selections": [
    (v10/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "combinedSlug",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v21 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 20
  }
],
v22 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "User",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v10/*: any*/),
      (v5/*: any*/),
      (v4/*: any*/),
      {
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
      }
    ],
    "storageKey": null
  }
],
v23 = [
  (v13/*: any*/),
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v28 = {
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
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v4/*: any*/),
    (v12/*: any*/),
    (v29/*: any*/),
    (v10/*: any*/)
  ],
  "storageKey": null
},
v31 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v32 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": (v31/*: any*/),
  "concreteType": "ProjectV2ItemConnection",
  "kind": "LinkedField",
  "name": "projectItemsNext",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "ProjectV2ItemEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "ProjectV2Item",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": [
            (v10/*: any*/),
            (v29/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "title",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v20/*: any*/),
                (v17/*: any*/),
                {
                  "alias": null,
                  "args": (v32/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v9/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v10/*: any*/),
                        (v4/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v10/*: any*/),
                            (v33/*: any*/),
                            (v4/*: any*/),
                            (v25/*: any*/),
                            (v24/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v26/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v15/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "closed",
                  "storageKey": null
                },
                (v8/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v9/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v32/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v33/*: any*/),
                    (v4/*: any*/),
                    (v25/*: any*/),
                    (v24/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v15/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v9/*: any*/)
          ],
          "storageKey": null
        },
        (v27/*: any*/)
      ],
      "storageKey": null
    },
    (v28/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v35 = {
  "alias": null,
  "args": (v31/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "DetailsPaneQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "owner",
            "plural": false,
            "selections": (v6/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": (v7/*: any*/),
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "pullRequest",
            "plural": false,
            "selections": [
              (v8/*: any*/),
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "DetailsPane_pullRequest"
              }
            ],
            "storageKey": null
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
      (v2/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "DetailsPaneQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          (v12/*: any*/),
          {
            "alias": null,
            "args": (v7/*: any*/),
            "concreteType": "PullRequest",
            "kind": "LinkedField",
            "name": "pullRequest",
            "plural": false,
            "selections": [
              (v8/*: any*/),
              (v10/*: any*/),
              {
                "alias": null,
                "args": [
                  (v13/*: any*/)
                ],
                "concreteType": "ReviewRequestConnection",
                "kind": "LinkedField",
                "name": "reviewRequests",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "ReviewRequestEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "ReviewRequest",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v14/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "ReviewRequest",
                            "kind": "LinkedField",
                            "name": "assignedFromReviewRequest",
                            "plural": false,
                            "selections": [
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "requestedReviewer",
                                "plural": false,
                                "selections": [
                                  (v9/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v10/*: any*/),
                                      (v4/*: any*/)
                                    ],
                                    "type": "Team",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v10/*: any*/),
                                      (v5/*: any*/)
                                    ],
                                    "type": "User",
                                    "abstractKey": null
                                  },
                                  (v15/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v14/*: any*/),
                              (v10/*: any*/)
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "requestedReviewer",
                            "plural": false,
                            "selections": [
                              (v9/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v10/*: any*/),
                                  (v16/*: any*/),
                                  (v5/*: any*/),
                                  (v17/*: any*/)
                                ],
                                "type": "User",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v18/*: any*/),
                                  (v10/*: any*/),
                                  {
                                    "alias": "teamAvatarUrl",
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "avatarUrl",
                                    "storageKey": null
                                  },
                                  (v4/*: any*/),
                                  (v17/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Organization",
                                    "kind": "LinkedField",
                                    "name": "organization",
                                    "plural": false,
                                    "selections": [
                                      (v4/*: any*/),
                                      (v10/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "type": "Team",
                                "abstractKey": null
                              },
                              (v15/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v10/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "reviewRequests(first:100)"
              },
              {
                "alias": null,
                "args": [
                  (v13/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "preferOpinionatedReviews",
                    "value": true
                  }
                ],
                "concreteType": "PullRequestReviewConnection",
                "kind": "LinkedField",
                "name": "latestReviews",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequestReviewEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestReview",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "OnBehalfOfReviewer",
                            "kind": "LinkedField",
                            "name": "onBehalfOfReviewers",
                            "plural": true,
                            "selections": [
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "asCodeowner",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "reviewer",
                                "plural": false,
                                "selections": [
                                  (v9/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v18/*: any*/)
                                    ],
                                    "type": "Team",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v6/*: any*/),
                                    "type": "User",
                                    "abstractKey": null
                                  },
                                  (v15/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "author",
                            "plural": false,
                            "selections": [
                              (v9/*: any*/),
                              (v16/*: any*/),
                              (v5/*: any*/),
                              (v17/*: any*/),
                              (v10/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v19/*: any*/),
                          (v10/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "latestReviews(first:100,preferOpinionatedReviews:true)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isDraft",
                "storageKey": null
              },
              (v19/*: any*/),
              (v20/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "codeowners",
                "plural": true,
                "selections": [
                  (v9/*: any*/),
                  (v15/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanAssign",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "baseRepository",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v10/*: any*/),
                  {
                    "alias": "planSupportsDraftPullRequests",
                    "args": [
                      {
                        "kind": "Literal",
                        "name": "feature",
                        "value": "DRAFT_PRS"
                      }
                    ],
                    "kind": "ScalarField",
                    "name": "planSupports",
                    "storageKey": "planSupports(feature:\"DRAFT_PRS\")"
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "baseRepositoryOwner",
                "plural": false,
                "selections": (v11/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v21/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": (v22/*: any*/),
                "storageKey": "assignees(first:20)"
              },
              {
                "alias": null,
                "args": (v21/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "suggestedAssignees",
                "plural": false,
                "selections": (v22/*: any*/),
                "storageKey": "suggestedAssignees(first:20)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v23/*: any*/),
                    "concreteType": "LabelConnection",
                    "kind": "LinkedField",
                    "name": "labels",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "LabelEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Label",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              (v10/*: any*/),
                              (v24/*: any*/),
                              (v4/*: any*/),
                              (v25/*: any*/),
                              (v26/*: any*/),
                              (v17/*: any*/),
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v27/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v28/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v23/*: any*/),
                    "filters": [
                      "orderBy"
                    ],
                    "handle": "connection",
                    "key": "LabelPicker_labels",
                    "kind": "LinkedHandle",
                    "name": "labels"
                  },
                  {
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isNode"
                  }
                ],
                "type": "Labelable",
                "abstractKey": "__isLabelable"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v30/*: any*/),
                      (v34/*: any*/),
                      (v35/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "viewerCanUpdateMetadata",
                        "storageKey": null
                      }
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v30/*: any*/),
                      (v34/*: any*/),
                      (v35/*: any*/)
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
          },
          (v10/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "c8055681c0c3e5712b04389d3a2d0d54",
    "metadata": {},
    "name": "DetailsPaneQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "30c90bf60249840a06f96e1b25e21e14";

export default node;
