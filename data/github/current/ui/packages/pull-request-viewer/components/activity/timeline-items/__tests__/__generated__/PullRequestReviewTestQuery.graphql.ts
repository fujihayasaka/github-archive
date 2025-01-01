/**
 * @generated SignedSource<<c6992c59b17ed9331d5e461c29ed7620>>
 * @relayHash 86b070c98358910b6f7bcf962a2439ff
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 86b070c98358910b6f7bcf962a2439ff

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestReviewTestQuery$variables = {
  pullRequestReviewId: string;
};
export type PullRequestReviewTestQuery$data = {
  readonly pullRequestReview: {
    readonly " $fragmentSpreads": FragmentRefs<"PullRequestReview_pullRequestReview">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"Thread_viewer">;
  };
};
export type PullRequestReviewTestQuery = {
  response: PullRequestReviewTestQuery$data;
  variables: PullRequestReviewTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "pullRequestReviewId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "pullRequestReviewId"
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
  "name": "databaseId",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authorAssociation",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v9 = [
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
    "concreteType": null,
    "kind": "LinkedField",
    "name": "author",
    "plural": false,
    "selections": [
      (v2/*: any*/),
      (v5/*: any*/),
      (v3/*: any*/)
    ],
    "storageKey": null
  },
  (v3/*: any*/)
],
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
  "name": "url",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isPrivate",
      "storageKey": null
    },
    (v10/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        (v2/*: any*/),
        (v3/*: any*/),
        (v5/*: any*/),
        (v11/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReport",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReportToMaintainer",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanBlockFromOrg",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUnblockFromOrg",
  "storageKey": null
},
v20 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "currentDiffResourcePath",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOutdated",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isResolved",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "path",
  "storageKey": null
},
v25 = {
  "kind": "ClientExtension",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__id",
      "storageKey": null
    }
  ]
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "subjectType",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v27/*: any*/),
    (v3/*: any*/),
    (v5/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v30 = {
  "alias": "isHidden",
  "args": null,
  "kind": "ScalarField",
  "name": "isMinimized",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "concreteType": "UserContentEdit",
  "kind": "LinkedField",
  "name": "lastUserContentEdit",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "editor",
      "plural": false,
      "selections": [
        (v2/*: any*/),
        (v5/*: any*/),
        (v11/*: any*/),
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    (v3/*: any*/)
  ],
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "minimizedReason",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "publishedAt",
  "storageKey": null
},
v34 = {
  "alias": "reference",
  "args": null,
  "concreteType": "PullRequest",
  "kind": "LinkedField",
  "name": "pullRequest",
  "plural": false,
  "selections": (v9/*: any*/),
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanMinimize",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeMinimizeButton",
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeUnminimizeButton",
  "storageKey": null
},
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerRelationship",
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stafftoolsUrl",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v42 = [
  (v5/*: any*/)
],
v43 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v44 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "ReactionGroup",
      "kind": "LinkedField",
      "name": "reactionGroups",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "content",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "viewerHasReacted",
          "storageKey": null
        },
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 5
            }
          ],
          "concreteType": "ReactorConnection",
          "kind": "LinkedField",
          "name": "reactors",
          "plural": false,
          "selections": [
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v2/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v42/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v42/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v42/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v42/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v43/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": "reactors(first:5)"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Reactable",
  "abstractKey": "__isReactable"
},
v45 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v46 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v47 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v48 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v49 = {
  "enumValues": [
    "COLLABORATOR",
    "CONTRIBUTOR",
    "FIRST_TIMER",
    "FIRST_TIME_CONTRIBUTOR",
    "MANNEQUIN",
    "MEMBER",
    "NONE",
    "OWNER"
  ],
  "nullable": false,
  "plural": false,
  "type": "CommentAuthorAssociation"
},
v50 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v51 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v52 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v53 = [
  "APPROVED",
  "CHANGES_REQUESTED",
  "COMMENTED",
  "DISMISSED",
  "PENDING"
],
v54 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v55 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v56 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v57 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequest"
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v61 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "ReactionGroup"
},
v62 = {
  "enumValues": [
    "CONFUSED",
    "EYES",
    "HEART",
    "HOORAY",
    "LAUGH",
    "ROCKET",
    "THUMBS_DOWN",
    "THUMBS_UP"
  ],
  "nullable": false,
  "plural": false,
  "type": "ReactionContent"
},
v63 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReactorConnection"
},
v64 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Reactor"
},
v65 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v66 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v67 = {
  "enumValues": [
    "PENDING",
    "SUBMITTED"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewCommentState"
},
v68 = {
  "enumValues": [
    "FILE",
    "LINE"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewThreadSubjectType"
},
v69 = [
  "LEFT",
  "RIGHT"
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "PullRequestReviewTestQuery",
    "selections": [
      {
        "alias": "pullRequestReview",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "PullRequestReview_pullRequestReview"
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "Thread_viewer"
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
    "name": "PullRequestReviewTestQuery",
    "selections": [
      {
        "alias": "pullRequestReview",
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
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v3/*: any*/),
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
                  },
                  (v5/*: any*/),
                  {
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isActor"
                  }
                ],
                "storageKey": null
              },
              (v6/*: any*/),
              (v7/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "bodyText",
                "storageKey": null
              },
              (v8/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequest",
                "kind": "LinkedField",
                "name": "pullRequest",
                "plural": false,
                "selections": (v9/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 10
                  }
                ],
                "concreteType": "TeamConnection",
                "kind": "LinkedField",
                "name": "onBehalfOf",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "TeamEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Team",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Organization",
                            "kind": "LinkedField",
                            "name": "organization",
                            "plural": false,
                            "selections": [
                              (v10/*: any*/),
                              (v3/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v10/*: any*/),
                          (v11/*: any*/),
                          (v3/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "onBehalfOf(first:10)"
              },
              (v12/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "dismissedReviewState",
                "storageKey": null
              },
              (v13/*: any*/),
              (v11/*: any*/),
              (v14/*: any*/),
              (v15/*: any*/),
              (v16/*: any*/),
              (v17/*: any*/),
              (v18/*: any*/),
              (v19/*: any*/),
              {
                "alias": null,
                "args": (v20/*: any*/),
                "concreteType": "PullRequestReviewCommentItemConnection",
                "kind": "LinkedField",
                "name": "pullRequestThreadsAndReplies",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequestReviewCommentItemEdge",
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
                          (v2/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v3/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "line",
                                "storageKey": null
                              },
                              (v21/*: any*/),
                              (v22/*: any*/),
                              (v23/*: any*/),
                              (v24/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": [
                                  (v2/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "originalStartLine",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "originalEndLine",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "startLine",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "endLine",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "startDiffSide",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "endDiffSide",
                                        "storageKey": null
                                      },
                                      {
                                        "alias": null,
                                        "args": [
                                          {
                                            "kind": "Literal",
                                            "name": "maxContextLines",
                                            "value": 3
                                          }
                                        ],
                                        "concreteType": "DiffLine",
                                        "kind": "LinkedField",
                                        "name": "diffLines",
                                        "plural": true,
                                        "selections": [
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "left",
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "right",
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "html",
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "text",
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "type",
                                            "storageKey": null
                                          },
                                          (v25/*: any*/)
                                        ],
                                        "storageKey": "diffLines(maxContextLines:3)"
                                      }
                                    ],
                                    "type": "PullRequestDiffThread",
                                    "abstractKey": null
                                  }
                                ],
                                "storageKey": null
                              },
                              (v26/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanReply",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": [
                                  {
                                    "kind": "Literal",
                                    "name": "first",
                                    "value": 50
                                  }
                                ],
                                "concreteType": "PullRequestReviewCommentConnection",
                                "kind": "LinkedField",
                                "name": "comments",
                                "plural": false,
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "PullRequestReviewCommentEdge",
                                    "kind": "LinkedField",
                                    "name": "edges",
                                    "plural": true,
                                    "selections": [
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": "PullRequestReviewComment",
                                        "kind": "LinkedField",
                                        "name": "node",
                                        "plural": false,
                                        "selections": [
                                          (v28/*: any*/),
                                          (v6/*: any*/),
                                          (v7/*: any*/),
                                          (v29/*: any*/),
                                          (v8/*: any*/),
                                          (v21/*: any*/),
                                          (v4/*: any*/),
                                          (v3/*: any*/),
                                          (v30/*: any*/),
                                          (v31/*: any*/),
                                          (v32/*: any*/),
                                          (v33/*: any*/),
                                          (v34/*: any*/),
                                          (v12/*: any*/),
                                          (v13/*: any*/),
                                          (v26/*: any*/),
                                          (v35/*: any*/),
                                          (v18/*: any*/),
                                          (v36/*: any*/),
                                          (v16/*: any*/),
                                          (v17/*: any*/),
                                          (v37/*: any*/),
                                          (v38/*: any*/),
                                          (v19/*: any*/),
                                          (v39/*: any*/),
                                          (v40/*: any*/),
                                          (v11/*: any*/),
                                          (v14/*: any*/),
                                          (v15/*: any*/),
                                          (v44/*: any*/)
                                        ],
                                        "storageKey": null
                                      }
                                    ],
                                    "storageKey": null
                                  },
                                  (v41/*: any*/),
                                  (v25/*: any*/)
                                ],
                                "storageKey": "comments(first:50)"
                              }
                            ],
                            "type": "PullRequestThread",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v3/*: any*/),
                              (v21/*: any*/),
                              (v24/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "PullRequestThread",
                                "kind": "LinkedField",
                                "name": "pullRequestThread",
                                "plural": false,
                                "selections": [
                                  (v3/*: any*/),
                                  (v22/*: any*/),
                                  (v23/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v28/*: any*/),
                              (v6/*: any*/),
                              (v7/*: any*/),
                              (v29/*: any*/),
                              (v8/*: any*/),
                              (v4/*: any*/),
                              (v30/*: any*/),
                              (v31/*: any*/),
                              (v32/*: any*/),
                              (v33/*: any*/),
                              (v34/*: any*/),
                              (v12/*: any*/),
                              (v13/*: any*/),
                              (v26/*: any*/),
                              (v35/*: any*/),
                              (v18/*: any*/),
                              (v36/*: any*/),
                              (v16/*: any*/),
                              (v17/*: any*/),
                              (v37/*: any*/),
                              (v38/*: any*/),
                              (v19/*: any*/),
                              (v39/*: any*/),
                              (v40/*: any*/),
                              (v11/*: any*/),
                              (v14/*: any*/),
                              (v15/*: any*/),
                              (v44/*: any*/)
                            ],
                            "type": "PullRequestReviewComment",
                            "abstractKey": null
                          },
                          (v43/*: any*/)
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
                "storageKey": "pullRequestThreadsAndReplies(first:100)"
              },
              {
                "alias": null,
                "args": (v20/*: any*/),
                "filters": null,
                "handle": "connection",
                "key": "PullRequestReview_pullRequestThreadsAndReplies",
                "kind": "LinkedHandle",
                "name": "pullRequestThreadsAndReplies"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanReadUserContentEdits",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "lastEditedAt",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "UserContentEdit",
                    "kind": "LinkedField",
                    "name": "lastUserContentEdit",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "editor",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          (v11/*: any*/),
                          (v5/*: any*/),
                          (v3/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v44/*: any*/),
              (v25/*: any*/)
            ],
            "type": "PullRequestReview",
            "abstractKey": null
          }
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          (v27/*: any*/),
          (v5/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isSiteAdmin",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "PullRequestUserPreferences",
            "kind": "LinkedField",
            "name": "pullRequestUserPreferences",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "tabSize",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "diffView",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v3/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "86b070c98358910b6f7bcf962a2439ff",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequestReview": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequestReview.__id": (v45/*: any*/),
        "pullRequestReview.__isComment": (v46/*: any*/),
        "pullRequestReview.__isReactable": (v46/*: any*/),
        "pullRequestReview.__typename": (v46/*: any*/),
        "pullRequestReview.author": (v47/*: any*/),
        "pullRequestReview.author.__isActor": (v46/*: any*/),
        "pullRequestReview.author.__typename": (v46/*: any*/),
        "pullRequestReview.author.avatarUrl": (v48/*: any*/),
        "pullRequestReview.author.id": (v45/*: any*/),
        "pullRequestReview.author.login": (v46/*: any*/),
        "pullRequestReview.authorAssociation": (v49/*: any*/),
        "pullRequestReview.bodyHTML": (v50/*: any*/),
        "pullRequestReview.bodyText": (v46/*: any*/),
        "pullRequestReview.createdAt": (v51/*: any*/),
        "pullRequestReview.databaseId": (v52/*: any*/),
        "pullRequestReview.dismissedReviewState": {
          "enumValues": (v53/*: any*/),
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewState"
        },
        "pullRequestReview.id": (v45/*: any*/),
        "pullRequestReview.lastEditedAt": (v54/*: any*/),
        "pullRequestReview.lastUserContentEdit": (v55/*: any*/),
        "pullRequestReview.lastUserContentEdit.editor": (v47/*: any*/),
        "pullRequestReview.lastUserContentEdit.editor.__typename": (v46/*: any*/),
        "pullRequestReview.lastUserContentEdit.editor.id": (v45/*: any*/),
        "pullRequestReview.lastUserContentEdit.editor.login": (v46/*: any*/),
        "pullRequestReview.lastUserContentEdit.editor.url": (v48/*: any*/),
        "pullRequestReview.lastUserContentEdit.id": (v45/*: any*/),
        "pullRequestReview.onBehalfOf": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "TeamConnection"
        },
        "pullRequestReview.onBehalfOf.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "TeamEdge"
        },
        "pullRequestReview.onBehalfOf.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Team"
        },
        "pullRequestReview.onBehalfOf.edges.node.id": (v45/*: any*/),
        "pullRequestReview.onBehalfOf.edges.node.name": (v46/*: any*/),
        "pullRequestReview.onBehalfOf.edges.node.organization": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Organization"
        },
        "pullRequestReview.onBehalfOf.edges.node.organization.id": (v45/*: any*/),
        "pullRequestReview.onBehalfOf.edges.node.organization.name": (v56/*: any*/),
        "pullRequestReview.onBehalfOf.edges.node.url": (v48/*: any*/),
        "pullRequestReview.pullRequest": (v57/*: any*/),
        "pullRequestReview.pullRequest.author": (v47/*: any*/),
        "pullRequestReview.pullRequest.author.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequest.author.id": (v45/*: any*/),
        "pullRequestReview.pullRequest.author.login": (v46/*: any*/),
        "pullRequestReview.pullRequest.id": (v45/*: any*/),
        "pullRequestReview.pullRequest.number": (v58/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewCommentItemConnection"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequestReviewCommentItemEdge"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.cursor": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewCommentItem"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.__isNode": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.__isReactable": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.author": (v47/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.author.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.author.avatarUrl": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.author.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.author.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.author.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.authorAssociation": (v49/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.body": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.bodyHTML": (v50/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PullRequestReviewCommentConnection"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.__id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequestReviewCommentEdge"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewComment"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.__isReactable": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author": (v47/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.avatarUrl": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.authorAssociation": (v49/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.body": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.bodyHTML": (v50/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.createdAt": (v51/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.currentDiffResourcePath": (v59/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.databaseId": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.isHidden": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit": (v55/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor": (v47/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.minimizedReason": (v56/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.publishedAt": (v54/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups": (v61/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.content": (v62/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors": (v63/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes": (v64/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.__isNode": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.totalCount": (v58/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.viewerHasReacted": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference": (v57/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author": (v47/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.number": (v58/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository": (v65/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.isPrivate": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.name": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner": (v66/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.stafftoolsUrl": (v59/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.state": (v67/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.subjectType": (v68/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanBlockFromOrg": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanDelete": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanMinimize": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanReport": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanReportToMaintainer": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanSeeMinimizeButton": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanSeeUnminimizeButton": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanUnblockFromOrg": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanUpdate": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerDidAuthor": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerRelationship": (v49/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.comments.totalCount": (v58/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.createdAt": (v51/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.currentDiffResourcePath": (v59/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.databaseId": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.isHidden": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.isOutdated": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.isResolved": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit": (v55/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor": (v47/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.line": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.minimizedReason": (v56/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.path": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.publishedAt": (v54/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.pullRequestThread": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestThread"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.pullRequestThread.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.pullRequestThread.isOutdated": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.pullRequestThread.isResolved": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups": (v61/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.content": (v62/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors": (v63/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes": (v64/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.__isNode": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.totalCount": (v58/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reactionGroups.viewerHasReacted": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference": (v57/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference.author": (v47/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference.author.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference.author.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference.author.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.reference.number": (v58/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository": (v65/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.isPrivate": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.name": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.owner": (v66/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.owner.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.owner.id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.owner.login": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.repository.owner.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.stafftoolsUrl": (v59/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.state": (v67/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PullRequestThreadSubject"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.__typename": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "DiffLine"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines.__id": (v45/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines.html": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines.left": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines.right": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines.text": (v46/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.diffLines.type": {
          "enumValues": [
            "ADDITION",
            "CONTEXT",
            "DELETION",
            "HUNK",
            "INJECTED_CONTEXT"
          ],
          "nullable": false,
          "plural": false,
          "type": "DiffLineType"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.endDiffSide": {
          "enumValues": (v69/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "DiffSide"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.endLine": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.originalEndLine": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.originalStartLine": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.startDiffSide": {
          "enumValues": (v69/*: any*/),
          "nullable": true,
          "plural": false,
          "type": "DiffSide"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subject.startLine": (v52/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.subjectType": (v68/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.url": (v48/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanBlockFromOrg": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanDelete": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanMinimize": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanReply": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanReport": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanReportToMaintainer": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanSeeMinimizeButton": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanSeeUnminimizeButton": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanUnblockFromOrg": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerCanUpdate": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerDidAuthor": (v60/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.edges.node.viewerRelationship": (v49/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "pullRequestReview.pullRequestThreadsAndReplies.pageInfo.endCursor": (v56/*: any*/),
        "pullRequestReview.pullRequestThreadsAndReplies.pageInfo.hasNextPage": (v60/*: any*/),
        "pullRequestReview.reactionGroups": (v61/*: any*/),
        "pullRequestReview.reactionGroups.content": (v62/*: any*/),
        "pullRequestReview.reactionGroups.reactors": (v63/*: any*/),
        "pullRequestReview.reactionGroups.reactors.nodes": (v64/*: any*/),
        "pullRequestReview.reactionGroups.reactors.nodes.__isNode": (v46/*: any*/),
        "pullRequestReview.reactionGroups.reactors.nodes.__typename": (v46/*: any*/),
        "pullRequestReview.reactionGroups.reactors.nodes.id": (v45/*: any*/),
        "pullRequestReview.reactionGroups.reactors.nodes.login": (v46/*: any*/),
        "pullRequestReview.reactionGroups.reactors.totalCount": (v58/*: any*/),
        "pullRequestReview.reactionGroups.viewerHasReacted": (v60/*: any*/),
        "pullRequestReview.repository": (v65/*: any*/),
        "pullRequestReview.repository.id": (v45/*: any*/),
        "pullRequestReview.repository.isPrivate": (v60/*: any*/),
        "pullRequestReview.repository.name": (v46/*: any*/),
        "pullRequestReview.repository.owner": (v66/*: any*/),
        "pullRequestReview.repository.owner.__typename": (v46/*: any*/),
        "pullRequestReview.repository.owner.id": (v45/*: any*/),
        "pullRequestReview.repository.owner.login": (v46/*: any*/),
        "pullRequestReview.repository.owner.url": (v48/*: any*/),
        "pullRequestReview.state": {
          "enumValues": (v53/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "PullRequestReviewState"
        },
        "pullRequestReview.url": (v48/*: any*/),
        "pullRequestReview.viewerCanBlockFromOrg": (v60/*: any*/),
        "pullRequestReview.viewerCanDelete": (v60/*: any*/),
        "pullRequestReview.viewerCanReadUserContentEdits": (v60/*: any*/),
        "pullRequestReview.viewerCanReport": (v60/*: any*/),
        "pullRequestReview.viewerCanReportToMaintainer": (v60/*: any*/),
        "pullRequestReview.viewerCanUnblockFromOrg": (v60/*: any*/),
        "pullRequestReview.viewerCanUpdate": (v60/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.avatarUrl": (v48/*: any*/),
        "viewer.id": (v45/*: any*/),
        "viewer.isSiteAdmin": (v60/*: any*/),
        "viewer.login": (v46/*: any*/),
        "viewer.pullRequestUserPreferences": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PullRequestUserPreferences"
        },
        "viewer.pullRequestUserPreferences.diffView": (v46/*: any*/),
        "viewer.pullRequestUserPreferences.tabSize": (v58/*: any*/)
      }
    },
    "name": "PullRequestReviewTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "8952ae40e009d1d82e4820b71e75d0c1";

export default node;
