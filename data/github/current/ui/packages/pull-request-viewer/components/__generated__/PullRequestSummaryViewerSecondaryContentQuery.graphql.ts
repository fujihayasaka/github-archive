/**
 * @generated SignedSource<<918a471303477554fb21a500e225d865>>
 * @relayHash d2d960334927b746c60aac8955198181
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d2d960334927b746c60aac8955198181

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestSummaryViewerSecondaryContentQuery$variables = {
  endOid?: string | null | undefined;
  number: number;
  owner: string;
  repo: string;
  startOid?: string | null | undefined;
  timelinePageSize?: number | null | undefined;
};
export type PullRequestSummaryViewerSecondaryContentQuery$data = {
  readonly repository: {
    readonly pullRequest: {
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"ActivityView_pullRequest" | "FilesChangedListing_pullRequest">;
    } | null | undefined;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"ActivityView_viewer">;
  };
};
export type PullRequestSummaryViewerSecondaryContentQuery = {
  response: PullRequestSummaryViewerSecondaryContentQuery$data;
  variables: PullRequestSummaryViewerSecondaryContentQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "endOid"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "startOid"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "timelinePageSize"
},
v6 = [
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
  "name": "id",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "path",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v13 = {
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
v14 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v15 = [
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "timelinePageSize"
  },
  (v13/*: any*/),
  (v14/*: any*/)
],
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authorAssociation",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanMinimize",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReport",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReportToMaintainer",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanBlockFromOrg",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUnblockFromOrg",
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
  "kind": "ScalarField",
  "name": "minimizedReason",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v8/*: any*/),
    (v9/*: any*/),
    (v21/*: any*/)
  ],
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v40 = [
  (v17/*: any*/),
  (v9/*: any*/),
  (v8/*: any*/)
],
v41 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": (v40/*: any*/),
  "storageKey": null
},
v42 = {
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
            (v17/*: any*/),
            (v21/*: any*/),
            (v9/*: any*/),
            (v8/*: any*/)
          ],
          "storageKey": null
        },
        (v8/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
},
v43 = [
  (v9/*: any*/)
],
v44 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v45 = {
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
            (v16/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v17/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v43/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v43/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v43/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v43/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v44/*: any*/)
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
v46 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/),
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
    (v20/*: any*/),
    (v21/*: any*/),
    (v22/*: any*/),
    (v23/*: any*/),
    (v24/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/),
    (v27/*: any*/),
    (v28/*: any*/),
    (v29/*: any*/),
    (v30/*: any*/),
    (v31/*: any*/),
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
    (v32/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Sponsorship",
      "kind": "LinkedField",
      "name": "authorToRepoOwnerSponsorship",
      "plural": false,
      "selections": [
        (v22/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isActive",
          "storageKey": null
        },
        (v8/*: any*/)
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
        (v17/*: any*/),
        (v8/*: any*/),
        (v9/*: any*/),
        (v10/*: any*/)
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
        (v8/*: any*/),
        (v33/*: any*/),
        (v34/*: any*/),
        (v35/*: any*/),
        (v36/*: any*/),
        (v37/*: any*/),
        (v18/*: any*/)
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
        (v38/*: any*/),
        (v8/*: any*/),
        (v39/*: any*/),
        (v18/*: any*/),
        (v41/*: any*/)
      ],
      "storageKey": null
    },
    (v42/*: any*/),
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
    (v45/*: any*/)
  ],
  "type": "IssueComment",
  "abstractKey": null
},
v47 = {
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
v48 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v49 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v8/*: any*/),
    (v47/*: any*/),
    (v9/*: any*/),
    (v48/*: any*/)
  ],
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyText",
  "storageKey": null
},
v52 = [
  (v38/*: any*/),
  (v41/*: any*/),
  (v8/*: any*/)
],
v53 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequest",
  "kind": "LinkedField",
  "name": "pullRequest",
  "plural": false,
  "selections": (v52/*: any*/),
  "storageKey": null
},
v54 = {
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
                (v33/*: any*/),
                (v8/*: any*/)
              ],
              "storageKey": null
            },
            (v33/*: any*/),
            (v21/*: any*/),
            (v8/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "onBehalfOf(first:10)"
},
v55 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v35/*: any*/),
    (v33/*: any*/),
    (v34/*: any*/)
  ],
  "storageKey": null
},
v56 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dismissedReviewState",
  "storageKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v58 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "currentDiffResourcePath",
  "storageKey": null
},
v60 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOutdated",
  "storageKey": null
},
v61 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isResolved",
  "storageKey": null
},
v62 = {
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
v63 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "subjectType",
  "storageKey": null
},
v64 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v10/*: any*/),
    (v8/*: any*/),
    (v9/*: any*/),
    (v21/*: any*/)
  ],
  "storageKey": null
},
v65 = {
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
        (v17/*: any*/),
        (v9/*: any*/),
        (v21/*: any*/),
        (v8/*: any*/)
      ],
      "storageKey": null
    },
    (v8/*: any*/)
  ],
  "storageKey": null
},
v66 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "publishedAt",
  "storageKey": null
},
v67 = {
  "alias": "reference",
  "args": null,
  "concreteType": "PullRequest",
  "kind": "LinkedField",
  "name": "pullRequest",
  "plural": false,
  "selections": (v52/*: any*/),
  "storageKey": null
},
v68 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeMinimizeButton",
  "storageKey": null
},
v69 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeUnminimizeButton",
  "storageKey": null
},
v70 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerRelationship",
  "storageKey": null
},
v71 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stafftoolsUrl",
  "storageKey": null
},
v72 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v73 = {
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
v74 = {
  "alias": null,
  "args": (v58/*: any*/),
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
            (v17/*: any*/),
            {
              "kind": "InlineFragment",
              "selections": [
                (v8/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "line",
                  "storageKey": null
                },
                (v59/*: any*/),
                (v60/*: any*/),
                (v61/*: any*/),
                (v11/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "subject",
                  "plural": false,
                  "selections": [
                    (v17/*: any*/),
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
                            (v62/*: any*/)
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
                (v63/*: any*/),
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
                            (v64/*: any*/),
                            (v23/*: any*/),
                            (v50/*: any*/),
                            (v19/*: any*/),
                            (v22/*: any*/),
                            (v59/*: any*/),
                            (v18/*: any*/),
                            (v8/*: any*/),
                            (v30/*: any*/),
                            (v65/*: any*/),
                            (v31/*: any*/),
                            (v66/*: any*/),
                            (v67/*: any*/),
                            (v55/*: any*/),
                            (v57/*: any*/),
                            (v63/*: any*/),
                            (v32/*: any*/),
                            (v28/*: any*/),
                            (v25/*: any*/),
                            (v26/*: any*/),
                            (v27/*: any*/),
                            (v68/*: any*/),
                            (v69/*: any*/),
                            (v29/*: any*/),
                            (v70/*: any*/),
                            (v71/*: any*/),
                            (v21/*: any*/),
                            (v24/*: any*/),
                            (v20/*: any*/),
                            (v45/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "storageKey": null
                    },
                    (v16/*: any*/),
                    (v62/*: any*/)
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
                (v8/*: any*/),
                (v59/*: any*/),
                (v11/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "PullRequestThread",
                  "kind": "LinkedField",
                  "name": "pullRequestThread",
                  "plural": false,
                  "selections": [
                    (v8/*: any*/),
                    (v60/*: any*/),
                    (v61/*: any*/)
                  ],
                  "storageKey": null
                },
                (v64/*: any*/),
                (v23/*: any*/),
                (v50/*: any*/),
                (v19/*: any*/),
                (v22/*: any*/),
                (v18/*: any*/),
                (v30/*: any*/),
                (v65/*: any*/),
                (v31/*: any*/),
                (v66/*: any*/),
                (v67/*: any*/),
                (v55/*: any*/),
                (v57/*: any*/),
                (v63/*: any*/),
                (v32/*: any*/),
                (v28/*: any*/),
                (v25/*: any*/),
                (v26/*: any*/),
                (v27/*: any*/),
                (v68/*: any*/),
                (v69/*: any*/),
                (v29/*: any*/),
                (v70/*: any*/),
                (v71/*: any*/),
                (v21/*: any*/),
                (v24/*: any*/),
                (v20/*: any*/),
                (v45/*: any*/)
              ],
              "type": "PullRequestReviewComment",
              "abstractKey": null
            },
            (v44/*: any*/)
          ],
          "storageKey": null
        },
        (v72/*: any*/)
      ],
      "storageKey": null
    },
    (v73/*: any*/)
  ],
  "storageKey": "pullRequestThreadsAndReplies(first:100)"
},
v75 = {
  "alias": null,
  "args": (v58/*: any*/),
  "filters": null,
  "handle": "connection",
  "key": "PullRequestReview_pullRequestThreadsAndReplies",
  "kind": "LinkedHandle",
  "name": "pullRequestThreadsAndReplies"
},
v76 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v77 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "oid",
  "storageKey": null
},
v78 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authoredDate",
  "storageKey": null
},
v79 = {
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
                    (v47/*: any*/),
                    (v9/*: any*/),
                    (v17/*: any*/)
                  ],
                  "type": "Actor",
                  "abstractKey": "__isActor"
                },
                (v8/*: any*/)
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
v80 = {
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
        (v76/*: any*/),
        (v77/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "message",
          "storageKey": null
        },
        (v78/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "verificationStatus",
          "storageKey": null
        },
        (v79/*: any*/),
        (v8/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "PullRequestCommit",
  "abstractKey": null
},
v81 = [
  (v76/*: any*/),
  (v77/*: any*/),
  (v8/*: any*/)
],
v82 = [
  (v18/*: any*/),
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
    "selections": (v81/*: any*/),
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
      (v76/*: any*/),
      (v77/*: any*/),
      (v78/*: any*/),
      (v79/*: any*/),
      (v8/*: any*/)
    ],
    "storageKey": null
  }
],
v83 = {
  "kind": "InlineFragment",
  "selections": (v82/*: any*/),
  "type": "BaseRefForcePushedEvent",
  "abstractKey": null
},
v84 = {
  "kind": "InlineFragment",
  "selections": (v82/*: any*/),
  "type": "HeadRefForcePushedEvent",
  "abstractKey": null
},
v85 = {
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
v86 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v40/*: any*/),
  "storageKey": null
},
v87 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v33/*: any*/),
    (v35/*: any*/),
    (v86/*: any*/)
  ],
  "storageKey": null
},
v88 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v33/*: any*/),
    (v86/*: any*/),
    (v8/*: any*/)
  ],
  "storageKey": null
},
v89 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v48/*: any*/),
    (v47/*: any*/),
    (v9/*: any*/),
    (v8/*: any*/)
  ],
  "storageKey": null
},
v90 = {
  "kind": "InlineFragment",
  "selections": [
    (v18/*: any*/),
    (v22/*: any*/),
    (v85/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "duplicateOf",
      "plural": false,
      "selections": [
        (v17/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "kind": "InlineFragment",
              "selections": [
                (v8/*: any*/),
                {
                  "alias": "issueTitleHTML",
                  "args": null,
                  "kind": "ScalarField",
                  "name": "titleHTML",
                  "storageKey": null
                },
                (v21/*: any*/),
                (v38/*: any*/),
                (v85/*: any*/),
                (v87/*: any*/)
              ],
              "type": "Issue",
              "abstractKey": null
            },
            {
              "kind": "InlineFragment",
              "selections": [
                (v8/*: any*/),
                {
                  "alias": "pullTitleHTML",
                  "args": null,
                  "kind": "ScalarField",
                  "name": "titleHTML",
                  "storageKey": null
                },
                (v21/*: any*/),
                (v38/*: any*/),
                (v57/*: any*/),
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
                (v87/*: any*/)
              ],
              "type": "PullRequest",
              "abstractKey": null
            }
          ],
          "type": "ReferencedSubject",
          "abstractKey": "__isReferencedSubject"
        },
        (v44/*: any*/)
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
        (v17/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v21/*: any*/),
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
            (v21/*: any*/),
            (v38/*: any*/),
            (v88/*: any*/)
          ],
          "type": "PullRequest",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v21/*: any*/),
            (v76/*: any*/),
            (v88/*: any*/)
          ],
          "type": "Commit",
          "abstractKey": null
        },
        (v44/*: any*/)
      ],
      "storageKey": null
    },
    (v89/*: any*/)
  ],
  "type": "ClosedEvent",
  "abstractKey": null
},
v91 = {
  "kind": "InlineFragment",
  "selections": [
    (v18/*: any*/),
    (v22/*: any*/),
    (v89/*: any*/)
  ],
  "type": "ReopenedEvent",
  "abstractKey": null
},
v92 = {
  "kind": "InlineFragment",
  "selections": [
    (v18/*: any*/),
    (v89/*: any*/),
    {
      "alias": "mergeCommit",
      "args": null,
      "concreteType": "Commit",
      "kind": "LinkedField",
      "name": "commit",
      "plural": false,
      "selections": (v81/*: any*/),
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
    (v22/*: any*/)
  ],
  "type": "MergedEvent",
  "abstractKey": null
},
v93 = {
  "kind": "InlineFragment",
  "selections": [
    (v18/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "actor",
      "plural": false,
      "selections": [
        (v17/*: any*/),
        (v9/*: any*/),
        (v48/*: any*/),
        (v47/*: any*/),
        (v8/*: any*/)
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
            (v76/*: any*/),
            (v8/*: any*/)
          ],
          "storageKey": null
        },
        (v12/*: any*/),
        (v8/*: any*/)
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
        (v41/*: any*/),
        (v8/*: any*/)
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
    (v22/*: any*/)
  ],
  "type": "ReviewDismissedEvent",
  "abstractKey": null
},
v94 = {
  "kind": "InlineFragment",
  "selections": [
    (v18/*: any*/),
    (v89/*: any*/),
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
            (v17/*: any*/),
            {
              "kind": "InlineFragment",
              "selections": [
                (v9/*: any*/),
                (v12/*: any*/)
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
                (v12/*: any*/)
              ],
              "type": "Team",
              "abstractKey": null
            },
            (v44/*: any*/)
          ],
          "storageKey": null
        },
        (v8/*: any*/)
      ],
      "storageKey": null
    },
    (v22/*: any*/)
  ],
  "type": "ReviewRequestedEvent",
  "abstractKey": null
},
v95 = [
  "visibleEventsOnly",
  "itemTypes"
],
v96 = [
  (v13/*: any*/),
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v14/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "PullRequestSummaryViewerSecondaryContentQuery",
    "selections": [
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
      },
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
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
                "name": "FilesChangedListing_pullRequest"
              },
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
      (v3/*: any*/),
      (v4/*: any*/),
      (v0/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Operation",
    "name": "PullRequestSummaryViewerSecondaryContentQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          (v9/*: any*/),
          (v10/*: any*/),
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
          (v8/*: any*/)
        ],
        "storageKey": null
      },
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
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
                "alias": null,
                "args": [
                  {
                    "kind": "Variable",
                    "name": "endOid",
                    "variableName": "endOid"
                  },
                  {
                    "kind": "Variable",
                    "name": "startOid",
                    "variableName": "startOid"
                  }
                ],
                "concreteType": "PullRequestComparison",
                "kind": "LinkedField",
                "name": "comparison",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "linesAdded",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "linesDeleted",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequestSummaryDelta",
                    "kind": "LinkedField",
                    "name": "summary",
                    "plural": true,
                    "selections": [
                      (v11/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "additions",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "changeType",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "deletions",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "pathDigest",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "unresolvedCommentCount",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v12/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanComment",
                "storageKey": null
              },
              {
                "alias": "forwardTimeline",
                "args": (v15/*: any*/),
                "concreteType": "PullRequestTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v16/*: any*/),
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
                          (v17/*: any*/),
                          (v46/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v18/*: any*/),
                              (v49/*: any*/),
                              (v23/*: any*/),
                              (v50/*: any*/),
                              (v51/*: any*/),
                              (v22/*: any*/),
                              (v53/*: any*/),
                              (v54/*: any*/),
                              (v55/*: any*/),
                              (v56/*: any*/),
                              (v57/*: any*/),
                              (v21/*: any*/),
                              (v24/*: any*/),
                              (v20/*: any*/),
                              (v26/*: any*/),
                              (v27/*: any*/),
                              (v28/*: any*/),
                              (v29/*: any*/),
                              (v74/*: any*/),
                              (v75/*: any*/),
                              (v42/*: any*/),
                              (v45/*: any*/),
                              (v62/*: any*/)
                            ],
                            "type": "PullRequestReview",
                            "abstractKey": null
                          },
                          (v45/*: any*/),
                          (v80/*: any*/),
                          (v83/*: any*/),
                          (v84/*: any*/),
                          (v90/*: any*/),
                          (v91/*: any*/),
                          (v92/*: any*/),
                          (v93/*: any*/),
                          (v94/*: any*/),
                          (v44/*: any*/),
                          (v62/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v72/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v73/*: any*/),
                  (v62/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "forwardTimeline",
                "args": (v15/*: any*/),
                "filters": (v95/*: any*/),
                "handle": "connection",
                "key": "PullRequestTimelineForwardPagination_forwardTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backwardTimeline",
                "args": (v96/*: any*/),
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
                          (v17/*: any*/),
                          (v46/*: any*/),
                          (v45/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v18/*: any*/),
                              (v49/*: any*/),
                              (v23/*: any*/),
                              (v50/*: any*/),
                              (v51/*: any*/),
                              (v22/*: any*/),
                              (v53/*: any*/),
                              (v54/*: any*/),
                              (v55/*: any*/),
                              (v56/*: any*/),
                              (v57/*: any*/),
                              (v21/*: any*/),
                              (v24/*: any*/),
                              (v20/*: any*/),
                              (v26/*: any*/),
                              (v27/*: any*/),
                              (v28/*: any*/),
                              (v29/*: any*/),
                              (v74/*: any*/),
                              (v75/*: any*/),
                              (v42/*: any*/),
                              (v62/*: any*/)
                            ],
                            "type": "PullRequestReview",
                            "abstractKey": null
                          },
                          (v80/*: any*/),
                          (v83/*: any*/),
                          (v84/*: any*/),
                          (v90/*: any*/),
                          (v91/*: any*/),
                          (v92/*: any*/),
                          (v93/*: any*/),
                          (v94/*: any*/),
                          (v44/*: any*/),
                          (v62/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v72/*: any*/)
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
                  (v62/*: any*/)
                ],
                "storageKey": "timelineItems(itemTypes:[\"ISSUE_COMMENT\",\"PULL_REQUEST_REVIEW\",\"PULL_REQUEST_COMMIT\",\"BASE_REF_FORCE_PUSHED_EVENT\",\"HEAD_REF_FORCE_PUSHED_EVENT\",\"CLOSED_EVENT\",\"REOPENED_EVENT\",\"MERGED_EVENT\",\"REVIEW_DISMISSED_EVENT\",\"REVIEW_REQUESTED_EVENT\"],last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backwardTimeline",
                "args": (v96/*: any*/),
                "filters": (v95/*: any*/),
                "handle": "connection",
                "key": "PullRequestTimelineBackwardPagination_backwardTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              (v39/*: any*/),
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
              (v18/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v18/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  },
                  (v37/*: any*/),
                  (v36/*: any*/),
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
                  (v8/*: any*/),
                  (v21/*: any*/)
                ],
                "storageKey": null
              },
              (v57/*: any*/),
              (v21/*: any*/),
              (v41/*: any*/)
            ],
            "storageKey": null
          },
          (v8/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "d2d960334927b746c60aac8955198181",
    "metadata": {},
    "name": "PullRequestSummaryViewerSecondaryContentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "5430a664ea3bb4fd0c3db5927c740a01";

export default node;
