/**
 * @generated SignedSource<<bf8783427007baa9586ac2fb5fd0e7b1>>
 * @relayHash 0914adc8e5e825828ad21e963c0517fb
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 0914adc8e5e825828ad21e963c0517fb

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DetailsPaneTestQuery$variables = Record<PropertyKey, never>;
export type DetailsPaneTestQuery$data = {
  readonly pullRequest: {
    readonly " $fragmentSpreads": FragmentRefs<"DetailsPane_pullRequest">;
  } | null | undefined;
};
export type DetailsPaneTestQuery = {
  response: DetailsPaneTestQuery$data;
  variables: DetailsPaneTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "test-id"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "kind": "Literal",
  "name": "first",
  "value": 100
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "asCodeOwner",
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
  "name": "login",
  "storageKey": null
},
v7 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "combinedSlug",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v14 = [
  (v1/*: any*/),
  (v6/*: any*/),
  (v2/*: any*/)
],
v15 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 20
  }
],
v16 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "User",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v2/*: any*/),
      (v6/*: any*/),
      (v5/*: any*/),
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
v17 = [
  (v3/*: any*/),
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v22 = {
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
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v24 = {
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
      "selections": (v14/*: any*/),
      "storageKey": null
    },
    (v23/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v25 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v26 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": (v25/*: any*/),
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
            (v2/*: any*/),
            (v23/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v2/*: any*/),
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
                (v12/*: any*/),
                (v9/*: any*/),
                {
                  "alias": null,
                  "args": (v26/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v1/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v2/*: any*/),
                        (v5/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v2/*: any*/),
                            (v27/*: any*/),
                            (v5/*: any*/),
                            (v19/*: any*/),
                            (v18/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v20/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v7/*: any*/)
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
                (v13/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v1/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v26/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v1/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v2/*: any*/),
                    (v27/*: any*/),
                    (v5/*: any*/),
                    (v19/*: any*/),
                    (v18/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v7/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v1/*: any*/)
          ],
          "storageKey": null
        },
        (v21/*: any*/)
      ],
      "storageKey": null
    },
    (v22/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v29 = {
  "alias": null,
  "args": (v25/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v32 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "User"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v35 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v36 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "RequestedReviewer"
},
v39 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v40 = {
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
  "type": "ProjectV2SingleSelectFieldOptionColor"
},
v41 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "ReviewRequest"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "DetailsPaneTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
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
                "args": null,
                "kind": "FragmentSpread",
                "name": "DetailsPane_pullRequest"
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "DetailsPaneTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": [
                  (v3/*: any*/)
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
                          (v4/*: any*/),
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
                                  (v1/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v2/*: any*/),
                                      (v5/*: any*/)
                                    ],
                                    "type": "Team",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v2/*: any*/),
                                      (v6/*: any*/)
                                    ],
                                    "type": "User",
                                    "abstractKey": null
                                  },
                                  (v7/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v4/*: any*/),
                              (v2/*: any*/)
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
                              (v1/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v2/*: any*/),
                                  (v8/*: any*/),
                                  (v6/*: any*/),
                                  (v9/*: any*/)
                                ],
                                "type": "User",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v10/*: any*/),
                                  (v2/*: any*/),
                                  {
                                    "alias": "teamAvatarUrl",
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "avatarUrl",
                                    "storageKey": null
                                  },
                                  (v5/*: any*/),
                                  (v9/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Organization",
                                    "kind": "LinkedField",
                                    "name": "organization",
                                    "plural": false,
                                    "selections": [
                                      (v5/*: any*/),
                                      (v2/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "type": "Team",
                                "abstractKey": null
                              },
                              (v7/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v2/*: any*/)
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
                  (v3/*: any*/),
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
                                  (v1/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v10/*: any*/)
                                    ],
                                    "type": "Team",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v6/*: any*/)
                                    ],
                                    "type": "User",
                                    "abstractKey": null
                                  },
                                  (v7/*: any*/)
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
                              (v1/*: any*/),
                              (v8/*: any*/),
                              (v6/*: any*/),
                              (v9/*: any*/),
                              (v2/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v11/*: any*/),
                          (v2/*: any*/)
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
              (v11/*: any*/),
              (v12/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "codeowners",
                "plural": true,
                "selections": [
                  (v1/*: any*/),
                  (v7/*: any*/)
                ],
                "storageKey": null
              },
              (v13/*: any*/),
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
                  (v5/*: any*/),
                  (v2/*: any*/),
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
                "selections": (v14/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v15/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": (v16/*: any*/),
                "storageKey": "assignees(first:20)"
              },
              {
                "alias": null,
                "args": (v15/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "suggestedAssignees",
                "plural": false,
                "selections": (v16/*: any*/),
                "storageKey": "suggestedAssignees(first:20)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v17/*: any*/),
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
                              (v2/*: any*/),
                              (v18/*: any*/),
                              (v5/*: any*/),
                              (v19/*: any*/),
                              (v20/*: any*/),
                              (v9/*: any*/),
                              (v1/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v21/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v22/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v17/*: any*/),
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
                      (v24/*: any*/),
                      (v28/*: any*/),
                      (v29/*: any*/),
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
                      (v24/*: any*/),
                      (v28/*: any*/),
                      (v29/*: any*/)
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
          }
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ]
  },
  "params": {
    "id": "0914adc8e5e825828ad21e963c0517fb",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequest": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequest.__isIssueOrPullRequest": (v30/*: any*/),
        "pullRequest.__isLabelable": (v30/*: any*/),
        "pullRequest.__isNode": (v30/*: any*/),
        "pullRequest.__typename": (v30/*: any*/),
        "pullRequest.assignees": (v31/*: any*/),
        "pullRequest.assignees.nodes": (v32/*: any*/),
        "pullRequest.assignees.nodes.avatarUrl": (v33/*: any*/),
        "pullRequest.assignees.nodes.id": (v34/*: any*/),
        "pullRequest.assignees.nodes.login": (v30/*: any*/),
        "pullRequest.assignees.nodes.name": (v35/*: any*/),
        "pullRequest.baseRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "pullRequest.baseRepository.id": (v34/*: any*/),
        "pullRequest.baseRepository.name": (v30/*: any*/),
        "pullRequest.baseRepository.planSupportsDraftPullRequests": (v36/*: any*/),
        "pullRequest.baseRepositoryOwner": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "pullRequest.baseRepositoryOwner.__typename": (v30/*: any*/),
        "pullRequest.baseRepositoryOwner.id": (v34/*: any*/),
        "pullRequest.baseRepositoryOwner.login": (v30/*: any*/),
        "pullRequest.codeowners": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Codeowners"
        },
        "pullRequest.codeowners.__isNode": (v30/*: any*/),
        "pullRequest.codeowners.__typename": (v30/*: any*/),
        "pullRequest.codeowners.id": (v34/*: any*/),
        "pullRequest.id": (v34/*: any*/),
        "pullRequest.isDraft": (v36/*: any*/),
        "pullRequest.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "pullRequest.labels.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LabelEdge"
        },
        "pullRequest.labels.edges.cursor": (v30/*: any*/),
        "pullRequest.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "pullRequest.labels.edges.node.__typename": (v30/*: any*/),
        "pullRequest.labels.edges.node.color": (v30/*: any*/),
        "pullRequest.labels.edges.node.description": (v35/*: any*/),
        "pullRequest.labels.edges.node.id": (v34/*: any*/),
        "pullRequest.labels.edges.node.name": (v30/*: any*/),
        "pullRequest.labels.edges.node.nameHTML": (v30/*: any*/),
        "pullRequest.labels.edges.node.url": (v33/*: any*/),
        "pullRequest.labels.pageInfo": (v37/*: any*/),
        "pullRequest.labels.pageInfo.endCursor": (v35/*: any*/),
        "pullRequest.labels.pageInfo.hasNextPage": (v36/*: any*/),
        "pullRequest.latestReviews": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewConnection"
        },
        "pullRequest.latestReviews.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequestReviewEdge"
        },
        "pullRequest.latestReviews.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestReview"
        },
        "pullRequest.latestReviews.edges.node.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "pullRequest.latestReviews.edges.node.author.__typename": (v30/*: any*/),
        "pullRequest.latestReviews.edges.node.author.avatarUrl": (v33/*: any*/),
        "pullRequest.latestReviews.edges.node.author.id": (v34/*: any*/),
        "pullRequest.latestReviews.edges.node.author.login": (v30/*: any*/),
        "pullRequest.latestReviews.edges.node.author.url": (v33/*: any*/),
        "pullRequest.latestReviews.edges.node.id": (v34/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "OnBehalfOfReviewer"
        },
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.asCodeowner": (v36/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.reviewer": (v38/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.reviewer.__isNode": (v30/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.reviewer.__typename": (v30/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.reviewer.combinedSlug": (v30/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.reviewer.id": (v34/*: any*/),
        "pullRequest.latestReviews.edges.node.onBehalfOfReviewers.reviewer.login": (v30/*: any*/),
        "pullRequest.latestReviews.edges.node.state": {
          "enumValues": [
            "APPROVED",
            "CHANGES_REQUESTED",
            "COMMENTED",
            "DISMISSED",
            "PENDING"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestReviewState"
        },
        "pullRequest.number": (v39/*: any*/),
        "pullRequest.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "pullRequest.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "pullRequest.projectItemsNext.edges.cursor": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "pullRequest.projectItemsNext.edges.node.__typename": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.__isNode": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.__typename": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.color": (v40/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.id": (v34/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.name": (v35/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v35/*: any*/),
        "pullRequest.projectItemsNext.edges.node.fieldValueByName.optionId": (v35/*: any*/),
        "pullRequest.projectItemsNext.edges.node.id": (v34/*: any*/),
        "pullRequest.projectItemsNext.edges.node.isArchived": (v36/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "pullRequest.projectItemsNext.edges.node.project.__typename": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.closed": (v36/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "pullRequest.projectItemsNext.edges.node.project.field.__isNode": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.__typename": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.id": (v34/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.name": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "pullRequest.projectItemsNext.edges.node.project.field.options.color": (v40/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options.description": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options.id": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options.name": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options.nameHTML": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.field.options.optionId": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v36/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.id": (v34/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.number": (v39/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.template": (v36/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.title": (v30/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.url": (v33/*: any*/),
        "pullRequest.projectItemsNext.edges.node.project.viewerCanUpdate": (v36/*: any*/),
        "pullRequest.projectItemsNext.pageInfo": (v37/*: any*/),
        "pullRequest.projectItemsNext.pageInfo.endCursor": (v35/*: any*/),
        "pullRequest.projectItemsNext.pageInfo.hasNextPage": (v36/*: any*/),
        "pullRequest.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "pullRequest.repository.id": (v34/*: any*/),
        "pullRequest.repository.isArchived": (v36/*: any*/),
        "pullRequest.repository.name": (v30/*: any*/),
        "pullRequest.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "pullRequest.repository.owner.__typename": (v30/*: any*/),
        "pullRequest.repository.owner.id": (v34/*: any*/),
        "pullRequest.repository.owner.login": (v30/*: any*/),
        "pullRequest.reviewRequests": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ReviewRequestConnection"
        },
        "pullRequest.reviewRequests.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ReviewRequestEdge"
        },
        "pullRequest.reviewRequests.edges.node": (v41/*: any*/),
        "pullRequest.reviewRequests.edges.node.asCodeOwner": (v36/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest": (v41/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.asCodeOwner": (v36/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.id": (v34/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.requestedReviewer": (v38/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.requestedReviewer.__isNode": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.requestedReviewer.__typename": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.requestedReviewer.id": (v34/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.requestedReviewer.login": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.assignedFromReviewRequest.requestedReviewer.name": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.id": (v34/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer": (v38/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.__isNode": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.__typename": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.avatarUrl": (v33/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.combinedSlug": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.id": (v34/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.login": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.name": (v30/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.organization": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Organization"
        },
        "pullRequest.reviewRequests.edges.node.requestedReviewer.organization.id": (v34/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.organization.name": (v35/*: any*/),
        "pullRequest.reviewRequests.edges.node.requestedReviewer.teamAvatarUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "pullRequest.reviewRequests.edges.node.requestedReviewer.url": (v33/*: any*/),
        "pullRequest.state": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "pullRequest.suggestedAssignees": (v31/*: any*/),
        "pullRequest.suggestedAssignees.nodes": (v32/*: any*/),
        "pullRequest.suggestedAssignees.nodes.avatarUrl": (v33/*: any*/),
        "pullRequest.suggestedAssignees.nodes.id": (v34/*: any*/),
        "pullRequest.suggestedAssignees.nodes.login": (v30/*: any*/),
        "pullRequest.suggestedAssignees.nodes.name": (v35/*: any*/),
        "pullRequest.viewerCanAssign": (v36/*: any*/),
        "pullRequest.viewerCanUpdate": (v36/*: any*/),
        "pullRequest.viewerCanUpdateMetadata": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "DetailsPaneTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e5a525988bf4c033f6b16a936d04006e";

export default node;
