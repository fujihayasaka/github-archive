/**
 * @generated SignedSource<<13d038af6c895bd824882774e8c934b2>>
 * @relayHash fcb01812f4a4e65be3c4fffa7e27c26c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fcb01812f4a4e65be3c4fffa7e27c26c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestActivityBackwardPaginationQuery$variables = {
  cursor?: string | null | undefined;
  id: string;
  last?: number | null | undefined;
};
export type PullRequestActivityBackwardPaginationQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"ActivityView_pullRequest_backwardPagination">;
  } | null | undefined;
};
export type PullRequestActivityBackwardPaginationQuery = {
  response: PullRequestActivityBackwardPaginationQuery$data;
  variables: PullRequestActivityBackwardPaginationQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "cursor"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "last"
},
v3 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v4 = {
  "kind": "Variable",
  "name": "last",
  "variableName": "last"
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v7 = [
  {
    "kind": "Variable",
    "name": "before",
    "variableName": "cursor"
  },
  {
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
  (v4/*: any*/),
  {
    "kind": "Literal",
    "name": "visibleEventsOnly",
    "value": true
  }
],
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
    (v5/*: any*/),
    (v6/*: any*/),
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
  "name": "number",
  "storageKey": null
},
v29 = [
  (v5/*: any*/),
  (v23/*: any*/),
  (v6/*: any*/)
],
v30 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": (v29/*: any*/),
  "storageKey": null
},
v31 = {
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
            (v5/*: any*/),
            (v11/*: any*/),
            (v23/*: any*/),
            (v6/*: any*/)
          ],
          "storageKey": null
        },
        (v6/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v33 = [
  (v23/*: any*/)
],
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v6/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v35 = {
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
            (v32/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v5/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v33/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v33/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v33/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v33/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v34/*: any*/)
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
v36 = {
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
v37 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": null
},
v39 = [
  (v28/*: any*/),
  (v30/*: any*/),
  (v6/*: any*/)
],
v40 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v6/*: any*/),
    (v27/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/)
  ],
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v42 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "currentDiffResourcePath",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOutdated",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isResolved",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "path",
  "storageKey": null
},
v47 = {
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
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "subjectType",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v24/*: any*/),
    (v6/*: any*/),
    (v23/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v50 = {
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
        (v5/*: any*/),
        (v23/*: any*/),
        (v11/*: any*/),
        (v6/*: any*/)
      ],
      "storageKey": null
    },
    (v6/*: any*/)
  ],
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "publishedAt",
  "storageKey": null
},
v52 = {
  "alias": "reference",
  "args": null,
  "concreteType": "PullRequest",
  "kind": "LinkedField",
  "name": "pullRequest",
  "plural": false,
  "selections": (v39/*: any*/),
  "storageKey": null
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeMinimizeButton",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanSeeUnminimizeButton",
  "storageKey": null
},
v55 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerRelationship",
  "storageKey": null
},
v56 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "stafftoolsUrl",
  "storageKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v58 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "oid",
  "storageKey": null
},
v60 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authoredDate",
  "storageKey": null
},
v61 = {
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
                    (v36/*: any*/),
                    (v23/*: any*/),
                    (v5/*: any*/)
                  ],
                  "type": "Actor",
                  "abstractKey": "__isActor"
                },
                (v6/*: any*/)
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
v62 = [
  (v58/*: any*/),
  (v59/*: any*/),
  (v6/*: any*/)
],
v63 = [
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
    "selections": (v62/*: any*/),
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
      (v58/*: any*/),
      (v59/*: any*/),
      (v60/*: any*/),
      (v61/*: any*/),
      (v6/*: any*/)
    ],
    "storageKey": null
  }
],
v64 = {
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
v65 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v29/*: any*/),
  "storageKey": null
},
v66 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v6/*: any*/),
    (v25/*: any*/),
    (v27/*: any*/),
    (v65/*: any*/)
  ],
  "storageKey": null
},
v67 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v25/*: any*/),
    (v65/*: any*/),
    (v6/*: any*/)
  ],
  "storageKey": null
},
v68 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v37/*: any*/),
    (v36/*: any*/),
    (v23/*: any*/),
    (v6/*: any*/)
  ],
  "storageKey": null
},
v69 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
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
    "name": "PullRequestActivityBackwardPaginationQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "cursor",
                "variableName": "cursor"
              },
              (v4/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "ActivityView_pullRequest_backwardPagination"
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
      (v0/*: any*/),
      (v2/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "PullRequestActivityBackwardPaginationQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v5/*: any*/),
          (v6/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": "backwardTimeline",
                "args": (v7/*: any*/),
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
                          (v5/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
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
                                  (v6/*: any*/)
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
                                  (v5/*: any*/),
                                  (v6/*: any*/),
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
                                  (v6/*: any*/),
                                  (v25/*: any*/),
                                  (v26/*: any*/),
                                  (v27/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slashCommandsEnabled",
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "nameWithOwner",
                                    "storageKey": null
                                  },
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
                                  (v28/*: any*/),
                                  (v6/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "locked",
                                    "storageKey": null
                                  },
                                  (v8/*: any*/),
                                  (v30/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v31/*: any*/),
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
                              (v35/*: any*/)
                            ],
                            "type": "IssueComment",
                            "abstractKey": null
                          },
                          (v35/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v6/*: any*/),
                              (v8/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "author",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  (v6/*: any*/),
                                  (v36/*: any*/),
                                  (v23/*: any*/),
                                  (v37/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v13/*: any*/),
                              (v38/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "bodyText",
                                "storageKey": null
                              },
                              (v12/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "PullRequest",
                                "kind": "LinkedField",
                                "name": "pullRequest",
                                "plural": false,
                                "selections": (v39/*: any*/),
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
                                              (v25/*: any*/),
                                              (v6/*: any*/)
                                            ],
                                            "storageKey": null
                                          },
                                          (v25/*: any*/),
                                          (v11/*: any*/),
                                          (v6/*: any*/)
                                        ],
                                        "storageKey": null
                                      }
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": "onBehalfOf(first:10)"
                              },
                              (v40/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "dismissedReviewState",
                                "storageKey": null
                              },
                              (v41/*: any*/),
                              (v11/*: any*/),
                              (v14/*: any*/),
                              (v10/*: any*/),
                              (v16/*: any*/),
                              (v17/*: any*/),
                              (v18/*: any*/),
                              (v19/*: any*/),
                              {
                                "alias": null,
                                "args": (v42/*: any*/),
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
                                          (v5/*: any*/),
                                          {
                                            "kind": "InlineFragment",
                                            "selections": [
                                              (v6/*: any*/),
                                              {
                                                "alias": null,
                                                "args": null,
                                                "kind": "ScalarField",
                                                "name": "line",
                                                "storageKey": null
                                              },
                                              (v43/*: any*/),
                                              (v44/*: any*/),
                                              (v45/*: any*/),
                                              (v46/*: any*/),
                                              {
                                                "alias": null,
                                                "args": null,
                                                "concreteType": null,
                                                "kind": "LinkedField",
                                                "name": "subject",
                                                "plural": false,
                                                "selections": [
                                                  (v5/*: any*/),
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
                                                          (v47/*: any*/)
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
                                              (v48/*: any*/),
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
                                                          (v49/*: any*/),
                                                          (v13/*: any*/),
                                                          (v38/*: any*/),
                                                          (v9/*: any*/),
                                                          (v12/*: any*/),
                                                          (v43/*: any*/),
                                                          (v8/*: any*/),
                                                          (v6/*: any*/),
                                                          (v20/*: any*/),
                                                          (v50/*: any*/),
                                                          (v21/*: any*/),
                                                          (v51/*: any*/),
                                                          (v52/*: any*/),
                                                          (v40/*: any*/),
                                                          (v41/*: any*/),
                                                          (v48/*: any*/),
                                                          (v22/*: any*/),
                                                          (v18/*: any*/),
                                                          (v15/*: any*/),
                                                          (v16/*: any*/),
                                                          (v17/*: any*/),
                                                          (v53/*: any*/),
                                                          (v54/*: any*/),
                                                          (v19/*: any*/),
                                                          (v55/*: any*/),
                                                          (v56/*: any*/),
                                                          (v11/*: any*/),
                                                          (v14/*: any*/),
                                                          (v10/*: any*/),
                                                          (v35/*: any*/)
                                                        ],
                                                        "storageKey": null
                                                      }
                                                    ],
                                                    "storageKey": null
                                                  },
                                                  (v32/*: any*/),
                                                  (v47/*: any*/)
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
                                              (v6/*: any*/),
                                              (v43/*: any*/),
                                              (v46/*: any*/),
                                              {
                                                "alias": null,
                                                "args": null,
                                                "concreteType": "PullRequestThread",
                                                "kind": "LinkedField",
                                                "name": "pullRequestThread",
                                                "plural": false,
                                                "selections": [
                                                  (v6/*: any*/),
                                                  (v44/*: any*/),
                                                  (v45/*: any*/)
                                                ],
                                                "storageKey": null
                                              },
                                              (v49/*: any*/),
                                              (v13/*: any*/),
                                              (v38/*: any*/),
                                              (v9/*: any*/),
                                              (v12/*: any*/),
                                              (v8/*: any*/),
                                              (v20/*: any*/),
                                              (v50/*: any*/),
                                              (v21/*: any*/),
                                              (v51/*: any*/),
                                              (v52/*: any*/),
                                              (v40/*: any*/),
                                              (v41/*: any*/),
                                              (v48/*: any*/),
                                              (v22/*: any*/),
                                              (v18/*: any*/),
                                              (v15/*: any*/),
                                              (v16/*: any*/),
                                              (v17/*: any*/),
                                              (v53/*: any*/),
                                              (v54/*: any*/),
                                              (v19/*: any*/),
                                              (v55/*: any*/),
                                              (v56/*: any*/),
                                              (v11/*: any*/),
                                              (v14/*: any*/),
                                              (v10/*: any*/),
                                              (v35/*: any*/)
                                            ],
                                            "type": "PullRequestReviewComment",
                                            "abstractKey": null
                                          },
                                          (v34/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v57/*: any*/)
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
                                "args": (v42/*: any*/),
                                "filters": null,
                                "handle": "connection",
                                "key": "PullRequestReview_pullRequestThreadsAndReplies",
                                "kind": "LinkedHandle",
                                "name": "pullRequestThreadsAndReplies"
                              },
                              (v31/*: any*/),
                              (v47/*: any*/)
                            ],
                            "type": "PullRequestReview",
                            "abstractKey": null
                          },
                          {
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
                                  (v58/*: any*/),
                                  (v59/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "message",
                                    "storageKey": null
                                  },
                                  (v60/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "verificationStatus",
                                    "storageKey": null
                                  },
                                  (v61/*: any*/),
                                  (v6/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "PullRequestCommit",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v63/*: any*/),
                            "type": "BaseRefForcePushedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v63/*: any*/),
                            "type": "HeadRefForcePushedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v12/*: any*/),
                              (v64/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "duplicateOf",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v6/*: any*/),
                                          {
                                            "alias": "issueTitleHTML",
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "titleHTML",
                                            "storageKey": null
                                          },
                                          (v11/*: any*/),
                                          (v28/*: any*/),
                                          (v64/*: any*/),
                                          (v66/*: any*/)
                                        ],
                                        "type": "Issue",
                                        "abstractKey": null
                                      },
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v6/*: any*/),
                                          {
                                            "alias": "pullTitleHTML",
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "titleHTML",
                                            "storageKey": null
                                          },
                                          (v11/*: any*/),
                                          (v28/*: any*/),
                                          (v41/*: any*/),
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
                                          (v66/*: any*/)
                                        ],
                                        "type": "PullRequest",
                                        "abstractKey": null
                                      }
                                    ],
                                    "type": "ReferencedSubject",
                                    "abstractKey": "__isReferencedSubject"
                                  },
                                  (v34/*: any*/)
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
                                  (v5/*: any*/),
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
                                      (v28/*: any*/),
                                      (v67/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v11/*: any*/),
                                      (v58/*: any*/),
                                      (v67/*: any*/)
                                    ],
                                    "type": "Commit",
                                    "abstractKey": null
                                  },
                                  (v34/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v68/*: any*/)
                            ],
                            "type": "ClosedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v12/*: any*/),
                              (v68/*: any*/)
                            ],
                            "type": "ReopenedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v68/*: any*/),
                              {
                                "alias": "mergeCommit",
                                "args": null,
                                "concreteType": "Commit",
                                "kind": "LinkedField",
                                "name": "commit",
                                "plural": false,
                                "selections": (v62/*: any*/),
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
                          {
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
                                  (v5/*: any*/),
                                  (v23/*: any*/),
                                  (v37/*: any*/),
                                  (v36/*: any*/),
                                  (v6/*: any*/)
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
                                      (v58/*: any*/),
                                      (v6/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v69/*: any*/),
                                  (v6/*: any*/)
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
                                  (v30/*: any*/),
                                  (v6/*: any*/)
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
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v68/*: any*/),
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
                                      (v5/*: any*/),
                                      {
                                        "kind": "InlineFragment",
                                        "selections": [
                                          (v23/*: any*/),
                                          (v69/*: any*/)
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
                                          (v69/*: any*/)
                                        ],
                                        "type": "Team",
                                        "abstractKey": null
                                      },
                                      (v34/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v6/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v12/*: any*/)
                            ],
                            "type": "ReviewRequestedEvent",
                            "abstractKey": null
                          },
                          (v34/*: any*/),
                          (v47/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v57/*: any*/)
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
                  (v47/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "backwardTimeline",
                "args": (v7/*: any*/),
                "filters": [
                  "visibleEventsOnly",
                  "itemTypes"
                ],
                "handle": "connection",
                "key": "PullRequestTimelineBackwardPagination_backwardTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "fcb01812f4a4e65be3c4fffa7e27c26c",
    "metadata": {},
    "name": "PullRequestActivityBackwardPaginationQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b88e02139535afc39cca37f8def02f8c";

export default node;
