/**
 * @generated SignedSource<<7acc202cc3fd584dac16a01862daea5b>>
 * @relayHash 7464a6235066ac07b5aedd98a6dac939
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7464a6235066ac07b5aedd98a6dac939

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ActivityViewTestQuery$variables = {
  pullRequestId: string;
  timelinePageSize: number;
};
export type ActivityViewTestQuery$data = {
  readonly pullRequest: {
    readonly " $fragmentSpreads": FragmentRefs<"ActivityView_pullRequest">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"ActivityView_viewer">;
  };
};
export type ActivityViewTestQuery = {
  response: ActivityViewTestQuery$data;
  variables: ActivityViewTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "pullRequestId"
  },
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "timelinePageSize"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "pullRequestId"
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
  "kind": "Literal",
  "name": "itemTypes",
  "value": [
    "ISSUE_COMMENT",
    "PULL_REQUEST_REVIEW",
    "PULL_REQUEST_COMMIT",
    "BASE_REF_FORCE_PUSHED_EVENT",
    "HEAD_REF_FORCE_PUSHED_EVENT",
    "CLOSED_EVENT",
    "REOPENED_EVENT",
    "MERGED_EVENT",
    "REVIEW_DISMISSED_EVENT",
    "REVIEW_REQUESTED_EVENT"
  ]
},
v5 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v6 = [
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "timelinePageSize"
  },
  (v4/*: any*/),
  (v5/*: any*/)
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
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
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authorAssociation",
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
  "name": "viewerCanMinimize",
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
v20 = {
  "alias": "isHidden",
  "args": null,
  "kind": "ScalarField",
  "name": "isMinimized",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "minimizedReason",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v3/*: any*/),
    (v23/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v32 = [
  (v2/*: any*/),
  (v23/*: any*/),
  (v3/*: any*/)
],
v33 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": (v32/*: any*/),
  "storageKey": null
},
v34 = {
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
            (v23/*: any*/),
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
v35 = [
  (v23/*: any*/)
],
v36 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v37 = {
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
            (v7/*: any*/),
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
                  "selections": (v35/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v35/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v35/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v35/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v36/*: any*/)
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
v38 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v8/*: any*/),
    (v9/*: any*/),
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "unfurlReferences",
          "value": true
        }
      ],
      "kind": "ScalarField",
      "name": "bodyHTML",
      "storageKey": "bodyHTML(unfurlReferences:true)"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "bodyVersion",
      "storageKey": null
    },
    (v10/*: any*/),
    (v11/*: any*/),
    (v12/*: any*/),
    (v13/*: any*/),
    (v14/*: any*/),
    (v15/*: any*/),
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
      "name": "showSpammyBadge",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "createdViaEmail",
      "storageKey": null
    },
    (v22/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Sponsorship",
      "kind": "LinkedField",
      "name": "authorToRepoOwnerSponsorship",
      "plural": false,
      "selections": [
        (v12/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isActive",
          "storageKey": null
        },
        (v3/*: any*/)
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
        (v2/*: any*/),
        (v3/*: any*/),
        (v23/*: any*/),
        (v24/*: any*/)
      ],
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
        (v3/*: any*/),
        (v25/*: any*/),
        (v26/*: any*/),
        (v27/*: any*/),
        (v28/*: any*/),
        (v29/*: any*/),
        (v8/*: any*/)
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Issue",
      "kind": "LinkedField",
      "name": "issue",
      "plural": false,
      "selections": [
        (v30/*: any*/),
        (v3/*: any*/),
        (v31/*: any*/),
        (v8/*: any*/),
        (v33/*: any*/)
      ],
      "storageKey": null
    },
    (v34/*: any*/),
    {
      "kind": "ClientExtension",
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pendingMinimizeReason",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pendingBlock",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pendingUnblock",
          "storageKey": null
        }
      ]
    },
    (v37/*: any*/)
  ],
  "type": "IssueComment",
  "abstractKey": null
},
v39 = {
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
v40 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v41 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v3/*: any*/),
    (v39/*: any*/),
    (v23/*: any*/),
    (v40/*: any*/)
  ],
  "storageKey": null
},
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyText",
  "storageKey": null
},
v44 = [
  (v30/*: any*/),
  (v33/*: any*/),
  (v3/*: any*/)
],
v45 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequest",
  "kind": "LinkedField",
  "name": "pullRequest",
  "plural": false,
  "selections": (v44/*: any*/),
  "storageKey": null
},
v46 = {
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
                (v25/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            },
            (v25/*: any*/),
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
v47 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v27/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/)
  ],
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dismissedReviewState",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v50 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "currentDiffResourcePath",
  "storageKey": null
},
v52 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOutdated",
  "storageKey": null
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isResolved",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "path",
  "storageKey": null
},
v55 = {
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
v56 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "subjectType",
  "storageKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v24/*: any*/),
    (v3/*: any*/),
    (v23/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v58 = {
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
        (v23/*: any*/),
        (v11/*: any*/),
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    (v3/*: any*/)
  ],
  "storageKey": null
},
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "publishedAt",
  "storageKey": null
},
v60 = {
  "alias": "reference",
  "args": null,
  "concreteType": "PullRequest",
  "kind": "LinkedField",
  "name": "pullRequest",
  "plural": false,
  "selections": (v44/*: any*/),
  "storageKey": null
},
v61 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeMinimizeButton",
  "storageKey": null
},
v62 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeUnminimizeButton",
  "storageKey": null
},
v63 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerRelationship",
  "storageKey": null
},
v64 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stafftoolsUrl",
  "storageKey": null
},
v65 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v66 = {
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
v67 = {
  "alias": null,
  "args": (v50/*: any*/),
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
                (v51/*: any*/),
                (v52/*: any*/),
                (v53/*: any*/),
                (v54/*: any*/),
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
                            (v55/*: any*/)
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
                (v56/*: any*/),
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
                            (v57/*: any*/),
                            (v13/*: any*/),
                            (v42/*: any*/),
                            (v9/*: any*/),
                            (v12/*: any*/),
                            (v51/*: any*/),
                            (v8/*: any*/),
                            (v3/*: any*/),
                            (v20/*: any*/),
                            (v58/*: any*/),
                            (v21/*: any*/),
                            (v59/*: any*/),
                            (v60/*: any*/),
                            (v47/*: any*/),
                            (v49/*: any*/),
                            (v56/*: any*/),
                            (v22/*: any*/),
                            (v18/*: any*/),
                            (v15/*: any*/),
                            (v16/*: any*/),
                            (v17/*: any*/),
                            (v61/*: any*/),
                            (v62/*: any*/),
                            (v19/*: any*/),
                            (v63/*: any*/),
                            (v64/*: any*/),
                            (v11/*: any*/),
                            (v14/*: any*/),
                            (v10/*: any*/),
                            (v37/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "storageKey": null
                    },
                    (v7/*: any*/),
                    (v55/*: any*/)
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
                (v51/*: any*/),
                (v54/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "PullRequestThread",
                  "kind": "LinkedField",
                  "name": "pullRequestThread",
                  "plural": false,
                  "selections": [
                    (v3/*: any*/),
                    (v52/*: any*/),
                    (v53/*: any*/)
                  ],
                  "storageKey": null
                },
                (v57/*: any*/),
                (v13/*: any*/),
                (v42/*: any*/),
                (v9/*: any*/),
                (v12/*: any*/),
                (v8/*: any*/),
                (v20/*: any*/),
                (v58/*: any*/),
                (v21/*: any*/),
                (v59/*: any*/),
                (v60/*: any*/),
                (v47/*: any*/),
                (v49/*: any*/),
                (v56/*: any*/),
                (v22/*: any*/),
                (v18/*: any*/),
                (v15/*: any*/),
                (v16/*: any*/),
                (v17/*: any*/),
                (v61/*: any*/),
                (v62/*: any*/),
                (v19/*: any*/),
                (v63/*: any*/),
                (v64/*: any*/),
                (v11/*: any*/),
                (v14/*: any*/),
                (v10/*: any*/),
                (v37/*: any*/)
              ],
              "type": "PullRequestReviewComment",
              "abstractKey": null
            },
            (v36/*: any*/)
          ],
          "storageKey": null
        },
        (v65/*: any*/)
      ],
      "storageKey": null
    },
    (v66/*: any*/)
  ],
  "storageKey": "pullRequestThreadsAndReplies(first:100)"
},
v68 = {
  "alias": null,
  "args": (v50/*: any*/),
  "filters": null,
  "handle": "connection",
  "key": "PullRequestReview_pullRequestThreadsAndReplies",
  "kind": "LinkedHandle",
  "name": "pullRequestThreadsAndReplies"
},
v69 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v70 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "oid",
  "storageKey": null
},
v71 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authoredDate",
  "storageKey": null
},
v72 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "first",
      "value": 1
    }
  ],
  "concreteType": "GitActorConnection",
  "kind": "LinkedField",
  "name": "authors",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "GitActorEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "GitActor",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "user",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v39/*: any*/),
                    (v23/*: any*/),
                    (v2/*: any*/)
                  ],
                  "type": "Actor",
                  "abstractKey": "__isActor"
                },
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "authors(first:1)"
},
v73 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "Commit",
      "kind": "LinkedField",
      "name": "commit",
      "plural": false,
      "selections": [
        (v69/*: any*/),
        (v70/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "message",
          "storageKey": null
        },
        (v71/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "verificationStatus",
          "storageKey": null
        },
        (v72/*: any*/),
        (v3/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "PullRequestCommit",
  "abstractKey": null
},
v74 = [
  (v69/*: any*/),
  (v70/*: any*/),
  (v3/*: any*/)
],
v75 = [
  (v8/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "refName",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "Commit",
    "kind": "LinkedField",
    "name": "beforeCommit",
    "plural": false,
    "selections": (v74/*: any*/),
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "Commit",
    "kind": "LinkedField",
    "name": "afterCommit",
    "plural": false,
    "selections": [
      (v69/*: any*/),
      (v70/*: any*/),
      (v71/*: any*/),
      (v72/*: any*/),
      (v3/*: any*/)
    ],
    "storageKey": null
  }
],
v76 = {
  "kind": "InlineFragment",
  "selections": (v75/*: any*/),
  "type": "BaseRefForcePushedEvent",
  "abstractKey": null
},
v77 = {
  "kind": "InlineFragment",
  "selections": (v75/*: any*/),
  "type": "HeadRefForcePushedEvent",
  "abstractKey": null
},
v78 = {
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
v79 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v32/*: any*/),
  "storageKey": null
},
v80 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v25/*: any*/),
    (v27/*: any*/),
    (v79/*: any*/)
  ],
  "storageKey": null
},
v81 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v25/*: any*/),
    (v79/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v82 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v40/*: any*/),
    (v39/*: any*/),
    (v23/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v83 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v12/*: any*/),
    (v78/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "duplicateOf",
      "plural": false,
      "selections": [
        (v2/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "kind": "InlineFragment",
              "selections": [
                (v3/*: any*/),
                {
                  "alias": "issueTitleHTML",
                  "args": null,
                  "kind": "ScalarField",
                  "name": "titleHTML",
                  "storageKey": null
                },
                (v11/*: any*/),
                (v30/*: any*/),
                (v78/*: any*/),
                (v80/*: any*/)
              ],
              "type": "Issue",
              "abstractKey": null
            },
            {
              "kind": "InlineFragment",
              "selections": [
                (v3/*: any*/),
                {
                  "alias": "pullTitleHTML",
                  "args": null,
                  "kind": "ScalarField",
                  "name": "titleHTML",
                  "storageKey": null
                },
                (v11/*: any*/),
                (v30/*: any*/),
                (v49/*: any*/),
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
                (v80/*: any*/)
              ],
              "type": "PullRequest",
              "abstractKey": null
            }
          ],
          "type": "ReferencedSubject",
          "abstractKey": "__isReferencedSubject"
        },
        (v36/*: any*/)
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "closingProjectItemStatus",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "closer",
      "plural": false,
      "selections": [
        (v2/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "title",
              "storageKey": null
            }
          ],
          "type": "ProjectV2",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v30/*: any*/),
            (v81/*: any*/)
          ],
          "type": "PullRequest",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v69/*: any*/),
            (v81/*: any*/)
          ],
          "type": "Commit",
          "abstractKey": null
        },
        (v36/*: any*/)
      ],
      "storageKey": null
    },
    (v82/*: any*/)
  ],
  "type": "ClosedEvent",
  "abstractKey": null
},
v84 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v12/*: any*/),
    (v82/*: any*/)
  ],
  "type": "ReopenedEvent",
  "abstractKey": null
},
v85 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v82/*: any*/),
    {
      "alias": "mergeCommit",
      "args": null,
      "concreteType": "Commit",
      "kind": "LinkedField",
      "name": "commit",
      "plural": false,
      "selections": (v74/*: any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "mergeRefName",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viaMergeQueue",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viaMergeQueueAPI",
      "storageKey": null
    },
    (v12/*: any*/)
  ],
  "type": "MergedEvent",
  "abstractKey": null
},
v86 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v87 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "actor",
      "plural": false,
      "selections": [
        (v2/*: any*/),
        (v23/*: any*/),
        (v40/*: any*/),
        (v39/*: any*/),
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "PullRequestCommit",
      "kind": "LinkedField",
      "name": "pullRequestCommit",
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
            (v69/*: any*/),
            (v3/*: any*/)
          ],
          "storageKey": null
        },
        (v86/*: any*/),
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "PullRequestReview",
      "kind": "LinkedField",
      "name": "review",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "fullDatabaseId",
          "storageKey": null
        },
        (v33/*: any*/),
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "dismissalMessageHTML",
      "storageKey": null
    },
    (v12/*: any*/)
  ],
  "type": "ReviewDismissedEvent",
  "abstractKey": null
},
v88 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v82/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "requestedReviewAssignedFromTeamName",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "ReviewRequest",
      "kind": "LinkedField",
      "name": "reviewRequest",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "codeOwnersResourcePath",
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
            (v2/*: any*/),
            {
              "kind": "InlineFragment",
              "selections": [
                (v23/*: any*/),
                (v86/*: any*/)
              ],
              "type": "User",
              "abstractKey": null
            },
            {
              "kind": "InlineFragment",
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "combinedSlug",
                  "storageKey": null
                },
                (v86/*: any*/)
              ],
              "type": "Team",
              "abstractKey": null
            },
            (v36/*: any*/)
          ],
          "storageKey": null
        },
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    (v12/*: any*/)
  ],
  "type": "ReviewRequestedEvent",
  "abstractKey": null
},
v89 = [
  "visibleEventsOnly",
  "itemTypes"
],
v90 = [
  (v4/*: any*/),
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v5/*: any*/)
],
v91 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v92 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v93 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v94 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestTimelineItemsConnection"
},
v95 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequestTimelineItemsEdge"
},
v96 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestTimelineItems"
},
v97 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v98 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v99 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v100 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitActorConnection"
},
v101 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "GitActorEdge"
},
v102 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitActor"
},
v103 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v104 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v105 = {
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
v106 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Sponsorship"
},
v107 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v108 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v109 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v110 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v111 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v112 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v113 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v114 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Commit"
},
v115 = {
  "enumValues": [
    "PARTIALLY_VERIFIED",
    "UNSIGNED",
    "UNVERIFIED",
    "VERIFIED"
  ],
  "nullable": true,
  "plural": false,
  "type": "CommitVerificationStatus"
},
v116 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v117 = [
  "APPROVED",
  "CHANGES_REQUESTED",
  "COMMENTED",
  "DISMISSED",
  "PENDING"
],
v118 = {
  "enumValues": (v117/*: any*/),
  "nullable": true,
  "plural": false,
  "type": "PullRequestReviewState"
},
v119 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v120 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v121 = {
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
v122 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v123 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v124 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v125 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "TeamConnection"
},
v126 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "TeamEdge"
},
v127 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Team"
},
v128 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Organization"
},
v129 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v130 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequest"
},
v131 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestCommit"
},
v132 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestReviewCommentItemConnection"
},
v133 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequestReviewCommentItemEdge"
},
v134 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestReviewCommentItem"
},
v135 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewCommentConnection"
},
v136 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequestReviewCommentEdge"
},
v137 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestReviewComment"
},
v138 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v139 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "ReactionGroup"
},
v140 = {
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
v141 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReactorConnection"
},
v142 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Reactor"
},
v143 = {
  "enumValues": [
    "PENDING",
    "SUBMITTED"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewCommentState"
},
v144 = {
  "enumValues": [
    "FILE",
    "LINE"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewThreadSubjectType"
},
v145 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestThread"
},
v146 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestThreadSubject"
},
v147 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "DiffLine"
},
v148 = {
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
v149 = [
  "LEFT",
  "RIGHT"
],
v150 = {
  "enumValues": (v149/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "DiffSide"
},
v151 = {
  "enumValues": (v149/*: any*/),
  "nullable": true,
  "plural": false,
  "type": "DiffSide"
},
v152 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v153 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestReview"
},
v154 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "BigInt"
},
v155 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "ReviewRequest"
},
v156 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "RequestedReviewer"
},
v157 = {
  "enumValues": (v117/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewState"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ActivityViewTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "timelinePageSize",
                "variableName": "timelinePageSize"
              }
            ],
            "kind": "FragmentSpread",
            "name": "ActivityView_pullRequest"
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
            "name": "ActivityView_viewer"
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
    "name": "ActivityViewTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
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
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanComment",
                "storageKey": null
              },
              {
                "alias": "forwardTimeline",
                "args": (v6/*: any*/),
                "concreteType": "PullRequestTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v7/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequestTimelineItemsEdge",
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
                          (v38/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v3/*: any*/),
                              (v8/*: any*/),
                              (v41/*: any*/),
                              (v13/*: any*/),
                              (v42/*: any*/),
                              (v43/*: any*/),
                              (v12/*: any*/),
                              (v45/*: any*/),
                              (v46/*: any*/),
                              (v47/*: any*/),
                              (v48/*: any*/),
                              (v49/*: any*/),
                              (v11/*: any*/),
                              (v14/*: any*/),
                              (v10/*: any*/),
                              (v16/*: any*/),
                              (v17/*: any*/),
                              (v18/*: any*/),
                              (v19/*: any*/),
                              (v67/*: any*/),
                              (v68/*: any*/),
                              (v34/*: any*/),
                              (v37/*: any*/),
                              (v55/*: any*/)
                            ],
                            "type": "PullRequestReview",
                            "abstractKey": null
                          },
                          (v37/*: any*/),
                          (v73/*: any*/),
                          (v76/*: any*/),
                          (v77/*: any*/),
                          (v83/*: any*/),
                          (v84/*: any*/),
                          (v85/*: any*/),
                          (v87/*: any*/),
                          (v88/*: any*/),
                          (v36/*: any*/),
                          (v55/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v65/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v66/*: any*/),
                  (v55/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "forwardTimeline",
                "args": (v6/*: any*/),
                "filters": (v89/*: any*/),
                "handle": "connection",
                "key": "PullRequestTimelineForwardPagination_forwardTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backwardTimeline",
                "args": (v90/*: any*/),
                "concreteType": "PullRequestTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequestTimelineItemsEdge",
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
                          (v38/*: any*/),
                          (v37/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v3/*: any*/),
                              (v8/*: any*/),
                              (v41/*: any*/),
                              (v13/*: any*/),
                              (v42/*: any*/),
                              (v43/*: any*/),
                              (v12/*: any*/),
                              (v45/*: any*/),
                              (v46/*: any*/),
                              (v47/*: any*/),
                              (v48/*: any*/),
                              (v49/*: any*/),
                              (v11/*: any*/),
                              (v14/*: any*/),
                              (v10/*: any*/),
                              (v16/*: any*/),
                              (v17/*: any*/),
                              (v18/*: any*/),
                              (v19/*: any*/),
                              (v67/*: any*/),
                              (v68/*: any*/),
                              (v34/*: any*/),
                              (v55/*: any*/)
                            ],
                            "type": "PullRequestReview",
                            "abstractKey": null
                          },
                          (v73/*: any*/),
                          (v76/*: any*/),
                          (v77/*: any*/),
                          (v83/*: any*/),
                          (v84/*: any*/),
                          (v85/*: any*/),
                          (v87/*: any*/),
                          (v88/*: any*/),
                          (v36/*: any*/),
                          (v55/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v65/*: any*/)
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
                        "name": "hasPreviousPage",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "startCursor",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v55/*: any*/)
                ],
                "storageKey": "timelineItems(itemTypes:[\"ISSUE_COMMENT\",\"PULL_REQUEST_REVIEW\",\"PULL_REQUEST_COMMIT\",\"BASE_REF_FORCE_PUSHED_EVENT\",\"HEAD_REF_FORCE_PUSHED_EVENT\",\"CLOSED_EVENT\",\"REOPENED_EVENT\",\"MERGED_EVENT\",\"REVIEW_DISMISSED_EVENT\",\"REVIEW_REQUESTED_EVENT\"],last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backwardTimeline",
                "args": (v90/*: any*/),
                "filters": (v89/*: any*/),
                "handle": "connection",
                "key": "PullRequestTimelineBackwardPagination_backwardTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              (v31/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanClose",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanReopen",
                "storageKey": null
              },
              (v8/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v8/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  },
                  (v29/*: any*/),
                  (v28/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "securityPolicyUrl",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "contributingFileUrl",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "codeOfConductFileUrl",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "visibility",
                    "storageKey": null
                  },
                  (v3/*: any*/),
                  (v11/*: any*/)
                ],
                "storageKey": null
              },
              (v49/*: any*/),
              (v11/*: any*/),
              (v33/*: any*/)
            ],
            "type": "PullRequest",
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
          (v23/*: any*/),
          (v24/*: any*/),
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
    "id": "7464a6235066ac07b5aedd98a6dac939",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequest": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequest.__typename": (v91/*: any*/),
        "pullRequest.author": (v92/*: any*/),
        "pullRequest.author.__typename": (v91/*: any*/),
        "pullRequest.author.id": (v93/*: any*/),
        "pullRequest.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline": (v94/*: any*/),
        "pullRequest.backwardTimeline.__id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges": (v95/*: any*/),
        "pullRequest.backwardTimeline.edges.cursor": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node": (v96/*: any*/),
        "pullRequest.backwardTimeline.edges.node.__id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.__isComment": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.__isReactable": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.actor": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.actor.__isActor": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.actor.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.actor.avatarUrl": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.actor.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.actor.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit": (v98/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authoredDate": (v99/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors": (v100/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges": (v101/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node": (v102/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node.user": (v103/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node.user.__isActor": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node.user.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node.user.avatarUrl": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node.user.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.authors.edges.node.user.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.afterCommit.oid": (v104/*: any*/),
        "pullRequest.backwardTimeline.edges.node.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.author.__isActor": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.author.avatarUrl": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.authorAssociation": (v105/*: any*/),
        "pullRequest.backwardTimeline.edges.node.authorToRepoOwnerSponsorship": (v106/*: any*/),
        "pullRequest.backwardTimeline.edges.node.authorToRepoOwnerSponsorship.createdAt": (v99/*: any*/),
        "pullRequest.backwardTimeline.edges.node.authorToRepoOwnerSponsorship.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.authorToRepoOwnerSponsorship.isActive": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.beforeCommit": (v98/*: any*/),
        "pullRequest.backwardTimeline.edges.node.beforeCommit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.beforeCommit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.beforeCommit.oid": (v104/*: any*/),
        "pullRequest.backwardTimeline.edges.node.body": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.bodyHTML": (v108/*: any*/),
        "pullRequest.backwardTimeline.edges.node.bodyText": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.bodyVersion": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer": (v109/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.abbreviatedOid": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.number": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository": (v111/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository.name": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository.owner": (v112/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository.owner.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.repository.owner.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.title": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closer.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.closingProjectItemStatus": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit": (v114/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authoredDate": (v99/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors": (v100/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges": (v101/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node": (v102/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node.user": (v103/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node.user.__isActor": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node.user.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node.user.avatarUrl": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node.user.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.authors.edges.node.user.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.message": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.oid": (v104/*: any*/),
        "pullRequest.backwardTimeline.edges.node.commit.verificationStatus": (v115/*: any*/),
        "pullRequest.backwardTimeline.edges.node.createdAt": (v99/*: any*/),
        "pullRequest.backwardTimeline.edges.node.createdViaEmail": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.databaseId": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.dismissalMessageHTML": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.dismissedReviewState": (v118/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf": (v119/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.__isReferencedSubject": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.isDraft": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.isInMergeQueue": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.issueTitleHTML": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.number": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.pullTitleHTML": (v108/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository": (v111/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.isPrivate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.name": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.owner": (v112/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.owner.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.repository.owner.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.state": (v120/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.stateReason": (v121/*: any*/),
        "pullRequest.backwardTimeline.edges.node.duplicateOf.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.isHidden": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue": (v122/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.databaseId": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.locked": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.issue.number": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastEditedAt": (v123/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit": (v124/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit.editor": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit.editor.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit.editor.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.mergeCommit": (v98/*: any*/),
        "pullRequest.backwardTimeline.edges.node.mergeCommit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.mergeCommit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.mergeCommit.oid": (v104/*: any*/),
        "pullRequest.backwardTimeline.edges.node.mergeRefName": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.minimizedReason": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf": (v125/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges": (v126/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node": (v127/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node.name": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node.organization": (v128/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node.organization.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node.organization.name": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.onBehalfOf.edges.node.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pendingBlock": (v129/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pendingMinimizeReason": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pendingUnblock": (v129/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest": (v130/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequest.number": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestCommit": (v131/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestCommit.commit": (v114/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestCommit.commit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestCommit.commit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestCommit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestCommit.resourcePath": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies": (v132/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges": (v133/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.cursor": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node": (v134/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.__isReactable": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.avatarUrl": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.authorAssociation": (v105/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.body": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.bodyHTML": (v108/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments": (v135/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.__id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges": (v136/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node": (v137/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.__isReactable": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.avatarUrl": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.authorAssociation": (v105/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.body": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.bodyHTML": (v108/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.createdAt": (v99/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.currentDiffResourcePath": (v138/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.databaseId": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.isHidden": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit": (v124/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.minimizedReason": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.publishedAt": (v123/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups": (v139/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.content": (v140/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.totalCount": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.viewerHasReacted": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference": (v130/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.number": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository": (v111/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.isPrivate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.name": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner": (v112/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.stafftoolsUrl": (v138/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.state": (v143/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.subjectType": (v144/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanBlockFromOrg": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanDelete": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanMinimize": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanReport": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanReportToMaintainer": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanSeeMinimizeButton": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanSeeUnminimizeButton": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanUnblockFromOrg": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanUpdate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerDidAuthor": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerRelationship": (v105/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.totalCount": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.createdAt": (v99/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.currentDiffResourcePath": (v138/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.databaseId": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.isHidden": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.isOutdated": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.isResolved": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit": (v124/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.line": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.minimizedReason": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.path": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.publishedAt": (v123/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread": (v145/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread.isOutdated": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread.isResolved": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups": (v139/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.content": (v140/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.totalCount": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.viewerHasReacted": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference": (v130/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.number": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository": (v111/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.isPrivate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.name": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner": (v112/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.stafftoolsUrl": (v138/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.state": (v143/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject": (v146/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines": (v147/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.__id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.html": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.left": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.right": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.text": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.type": (v148/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.endDiffSide": (v150/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.endLine": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.originalEndLine": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.originalStartLine": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.startDiffSide": (v151/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.startLine": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subjectType": (v144/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanBlockFromOrg": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanDelete": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanMinimize": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanReply": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanReport": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanReportToMaintainer": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanSeeMinimizeButton": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanSeeUnminimizeButton": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanUnblockFromOrg": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanUpdate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerDidAuthor": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerRelationship": (v105/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.pageInfo": (v152/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.pageInfo.endCursor": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.pullRequestThreadsAndReplies.pageInfo.hasNextPage": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups": (v139/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.content": (v140/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors.nodes.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors.nodes.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors.nodes.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.reactors.totalCount": (v110/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reactionGroups.viewerHasReacted": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.refName": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository": (v111/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.databaseId": (v116/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.isPrivate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.name": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.nameWithOwner": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.owner": (v112/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.owner.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.owner.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.owner.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.repository.slashCommandsEnabled": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.requestedReviewAssignedFromTeamName": (v113/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review": (v153/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review.author": (v92/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review.author.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review.author.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review.author.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review.fullDatabaseId": (v154/*: any*/),
        "pullRequest.backwardTimeline.edges.node.review.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest": (v155/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.codeOwnersResourcePath": (v138/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer": (v156/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer.__isNode": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer.__typename": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer.combinedSlug": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer.id": (v93/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer.login": (v91/*: any*/),
        "pullRequest.backwardTimeline.edges.node.reviewRequest.requestedReviewer.resourcePath": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.showSpammyBadge": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.state": (v157/*: any*/),
        "pullRequest.backwardTimeline.edges.node.stateReason": (v121/*: any*/),
        "pullRequest.backwardTimeline.edges.node.url": (v97/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viaMergeQueue": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viaMergeQueueAPI": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanBlockFromOrg": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanDelete": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanMinimize": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanReadUserContentEdits": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanReport": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanReportToMaintainer": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanUnblockFromOrg": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerCanUpdate": (v107/*: any*/),
        "pullRequest.backwardTimeline.edges.node.viewerDidAuthor": (v107/*: any*/),
        "pullRequest.backwardTimeline.pageInfo": (v152/*: any*/),
        "pullRequest.backwardTimeline.pageInfo.hasPreviousPage": (v107/*: any*/),
        "pullRequest.backwardTimeline.pageInfo.startCursor": (v113/*: any*/),
        "pullRequest.databaseId": (v116/*: any*/),
        "pullRequest.forwardTimeline": (v94/*: any*/),
        "pullRequest.forwardTimeline.__id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges": (v95/*: any*/),
        "pullRequest.forwardTimeline.edges.cursor": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node": (v96/*: any*/),
        "pullRequest.forwardTimeline.edges.node.__id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.__isComment": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.__isReactable": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.actor": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.actor.__isActor": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.actor.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.actor.avatarUrl": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.actor.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.actor.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit": (v98/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authoredDate": (v99/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors": (v100/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges": (v101/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node": (v102/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node.user": (v103/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node.user.__isActor": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node.user.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node.user.avatarUrl": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node.user.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.authors.edges.node.user.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.afterCommit.oid": (v104/*: any*/),
        "pullRequest.forwardTimeline.edges.node.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.author.__isActor": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.author.avatarUrl": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.authorAssociation": (v105/*: any*/),
        "pullRequest.forwardTimeline.edges.node.authorToRepoOwnerSponsorship": (v106/*: any*/),
        "pullRequest.forwardTimeline.edges.node.authorToRepoOwnerSponsorship.createdAt": (v99/*: any*/),
        "pullRequest.forwardTimeline.edges.node.authorToRepoOwnerSponsorship.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.authorToRepoOwnerSponsorship.isActive": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.beforeCommit": (v98/*: any*/),
        "pullRequest.forwardTimeline.edges.node.beforeCommit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.beforeCommit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.beforeCommit.oid": (v104/*: any*/),
        "pullRequest.forwardTimeline.edges.node.body": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.bodyHTML": (v108/*: any*/),
        "pullRequest.forwardTimeline.edges.node.bodyText": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.bodyVersion": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer": (v109/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.abbreviatedOid": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.number": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository": (v111/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository.name": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository.owner": (v112/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository.owner.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.repository.owner.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.title": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closer.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.closingProjectItemStatus": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit": (v114/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authoredDate": (v99/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors": (v100/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges": (v101/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node": (v102/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node.user": (v103/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node.user.__isActor": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node.user.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node.user.avatarUrl": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node.user.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.authors.edges.node.user.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.message": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.oid": (v104/*: any*/),
        "pullRequest.forwardTimeline.edges.node.commit.verificationStatus": (v115/*: any*/),
        "pullRequest.forwardTimeline.edges.node.createdAt": (v99/*: any*/),
        "pullRequest.forwardTimeline.edges.node.createdViaEmail": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.databaseId": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.dismissalMessageHTML": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.dismissedReviewState": (v118/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf": (v119/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.__isReferencedSubject": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.isDraft": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.isInMergeQueue": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.issueTitleHTML": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.number": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.pullTitleHTML": (v108/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository": (v111/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.isPrivate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.name": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.owner": (v112/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.owner.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.repository.owner.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.state": (v120/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.stateReason": (v121/*: any*/),
        "pullRequest.forwardTimeline.edges.node.duplicateOf.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.isHidden": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue": (v122/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.databaseId": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.locked": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.issue.number": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastEditedAt": (v123/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit": (v124/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit.editor": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit.editor.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit.editor.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.mergeCommit": (v98/*: any*/),
        "pullRequest.forwardTimeline.edges.node.mergeCommit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.mergeCommit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.mergeCommit.oid": (v104/*: any*/),
        "pullRequest.forwardTimeline.edges.node.mergeRefName": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.minimizedReason": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf": (v125/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges": (v126/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node": (v127/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node.name": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node.organization": (v128/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node.organization.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node.organization.name": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.onBehalfOf.edges.node.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pendingBlock": (v129/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pendingMinimizeReason": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pendingUnblock": (v129/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest": (v130/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequest.number": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestCommit": (v131/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestCommit.commit": (v114/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestCommit.commit.abbreviatedOid": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestCommit.commit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestCommit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestCommit.resourcePath": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies": (v132/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges": (v133/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.cursor": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node": (v134/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.__isReactable": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.avatarUrl": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.author.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.authorAssociation": (v105/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.body": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.bodyHTML": (v108/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments": (v135/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.__id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges": (v136/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node": (v137/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.__isReactable": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.avatarUrl": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.author.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.authorAssociation": (v105/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.body": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.bodyHTML": (v108/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.createdAt": (v99/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.currentDiffResourcePath": (v138/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.databaseId": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.isHidden": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit": (v124/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.minimizedReason": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.publishedAt": (v123/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups": (v139/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.content": (v140/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.nodes.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.reactors.totalCount": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reactionGroups.viewerHasReacted": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference": (v130/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.reference.number": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository": (v111/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.isPrivate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.name": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner": (v112/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.repository.owner.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.stafftoolsUrl": (v138/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.state": (v143/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.subjectType": (v144/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanBlockFromOrg": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanDelete": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanMinimize": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanReport": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanReportToMaintainer": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanSeeMinimizeButton": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanSeeUnminimizeButton": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanUnblockFromOrg": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerCanUpdate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerDidAuthor": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.edges.node.viewerRelationship": (v105/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.comments.totalCount": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.createdAt": (v99/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.currentDiffResourcePath": (v138/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.databaseId": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.isHidden": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.isOutdated": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.isResolved": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit": (v124/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.line": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.minimizedReason": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.path": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.publishedAt": (v123/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread": (v145/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread.isOutdated": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.pullRequestThread.isResolved": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups": (v139/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.content": (v140/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.nodes.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.reactors.totalCount": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reactionGroups.viewerHasReacted": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference": (v130/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.reference.number": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository": (v111/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.isPrivate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.name": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner": (v112/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.repository.owner.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.stafftoolsUrl": (v138/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.state": (v143/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject": (v146/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines": (v147/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.__id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.html": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.left": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.right": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.text": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.diffLines.type": (v148/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.endDiffSide": (v150/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.endLine": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.originalEndLine": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.originalStartLine": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.startDiffSide": (v151/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subject.startLine": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.subjectType": (v144/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanBlockFromOrg": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanDelete": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanMinimize": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanReply": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanReport": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanReportToMaintainer": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanSeeMinimizeButton": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanSeeUnminimizeButton": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanUnblockFromOrg": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerCanUpdate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerDidAuthor": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.edges.node.viewerRelationship": (v105/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.pageInfo": (v152/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.pageInfo.endCursor": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.pullRequestThreadsAndReplies.pageInfo.hasNextPage": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups": (v139/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.content": (v140/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors.nodes.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors.nodes.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors.nodes.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.reactors.totalCount": (v110/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reactionGroups.viewerHasReacted": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.refName": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository": (v111/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.databaseId": (v116/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.isPrivate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.name": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.nameWithOwner": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.owner": (v112/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.owner.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.owner.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.owner.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.owner.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.repository.slashCommandsEnabled": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.requestedReviewAssignedFromTeamName": (v113/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review": (v153/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review.author": (v92/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review.author.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review.author.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review.author.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review.fullDatabaseId": (v154/*: any*/),
        "pullRequest.forwardTimeline.edges.node.review.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest": (v155/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.codeOwnersResourcePath": (v138/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer": (v156/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer.__isNode": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer.__typename": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer.combinedSlug": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer.id": (v93/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer.login": (v91/*: any*/),
        "pullRequest.forwardTimeline.edges.node.reviewRequest.requestedReviewer.resourcePath": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.showSpammyBadge": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.state": (v157/*: any*/),
        "pullRequest.forwardTimeline.edges.node.stateReason": (v121/*: any*/),
        "pullRequest.forwardTimeline.edges.node.url": (v97/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viaMergeQueue": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viaMergeQueueAPI": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanBlockFromOrg": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanDelete": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanMinimize": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanReadUserContentEdits": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanReport": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanReportToMaintainer": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanUnblockFromOrg": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerCanUpdate": (v107/*: any*/),
        "pullRequest.forwardTimeline.edges.node.viewerDidAuthor": (v107/*: any*/),
        "pullRequest.forwardTimeline.pageInfo": (v152/*: any*/),
        "pullRequest.forwardTimeline.pageInfo.endCursor": (v113/*: any*/),
        "pullRequest.forwardTimeline.pageInfo.hasNextPage": (v107/*: any*/),
        "pullRequest.forwardTimeline.totalCount": (v110/*: any*/),
        "pullRequest.id": (v93/*: any*/),
        "pullRequest.locked": (v107/*: any*/),
        "pullRequest.repository": (v111/*: any*/),
        "pullRequest.repository.codeOfConductFileUrl": (v138/*: any*/),
        "pullRequest.repository.contributingFileUrl": (v138/*: any*/),
        "pullRequest.repository.databaseId": (v116/*: any*/),
        "pullRequest.repository.id": (v93/*: any*/),
        "pullRequest.repository.isArchived": (v107/*: any*/),
        "pullRequest.repository.nameWithOwner": (v91/*: any*/),
        "pullRequest.repository.securityPolicyUrl": (v138/*: any*/),
        "pullRequest.repository.slashCommandsEnabled": (v107/*: any*/),
        "pullRequest.repository.url": (v97/*: any*/),
        "pullRequest.repository.visibility": {
          "enumValues": [
            "INTERNAL",
            "PRIVATE",
            "PUBLIC"
          ],
          "nullable": false,
          "plural": false,
          "type": "RepositoryVisibility"
        },
        "pullRequest.state": (v120/*: any*/),
        "pullRequest.url": (v97/*: any*/),
        "pullRequest.viewerCanClose": (v107/*: any*/),
        "pullRequest.viewerCanComment": (v107/*: any*/),
        "pullRequest.viewerCanReopen": (v107/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.avatarUrl": (v97/*: any*/),
        "viewer.id": (v93/*: any*/),
        "viewer.isSiteAdmin": (v107/*: any*/),
        "viewer.login": (v91/*: any*/),
        "viewer.pullRequestUserPreferences": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PullRequestUserPreferences"
        },
        "viewer.pullRequestUserPreferences.diffView": (v91/*: any*/),
        "viewer.pullRequestUserPreferences.tabSize": (v110/*: any*/)
      }
    },
    "name": "ActivityViewTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "d21e9ee411a3745aecaed6edc2f13de3";

export default node;
