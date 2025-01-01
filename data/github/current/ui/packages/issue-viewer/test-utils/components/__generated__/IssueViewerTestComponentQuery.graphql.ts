/**
 * @generated SignedSource<<e8e53694d7f73fe7b8f0aa87ea3d34b0>>
 * @relayHash e35babb2f82d6fd31c3719e60541e170
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID e35babb2f82d6fd31c3719e60541e170

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerTestComponentQuery$variables = Record<PropertyKey, never>;
export type IssueViewerTestComponentQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerIssue">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
  } | null | undefined;
};
export type IssueViewerTestComponentQuery = {
  response: IssueViewerTestComponentQuery$data;
  variables: IssueViewerTestComponentQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "mockIssueId1"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "test-id-viewer"
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
  "name": "totalCount",
  "storageKey": null
},
v5 = [
  (v4/*: any*/)
],
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
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
  "name": "url",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v14 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v15 = [
  (v14/*: any*/)
],
v16 = [
  (v3/*: any*/)
],
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
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
  "name": "state",
  "storageKey": null
},
v22 = {
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
v23 = [
  (v2/*: any*/),
  (v9/*: any*/),
  (v3/*: any*/)
],
v24 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v23/*: any*/),
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v24/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v29 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v31 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v33 = {
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
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v36 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v37 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v36/*: any*/)
],
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v40 = {
  "kind": "InlineFragment",
  "selections": (v16/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v41 = {
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
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingBlock",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v47 = [
  (v9/*: any*/)
],
v48 = {
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
            (v4/*: any*/),
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
                  "selections": (v47/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v47/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v47/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v47/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v40/*: any*/)
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
v49 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v9/*: any*/),
    (v3/*: any*/),
    (v29/*: any*/),
    (v33/*: any*/)
  ],
  "storageKey": null
},
v50 = [
  (v2/*: any*/),
  (v40/*: any*/)
],
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v52 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "commonName",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "emailAddress",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "organization",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "organizationUnit",
    "storageKey": null
  }
],
v53 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v8/*: any*/),
    (v11/*: any*/),
    (v24/*: any*/)
  ],
  "storageKey": null
},
v55 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v53/*: any*/),
    (v10/*: any*/),
    (v18/*: any*/),
    (v22/*: any*/),
    (v54/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v56 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v58 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v56/*: any*/),
    (v10/*: any*/),
    (v18/*: any*/),
    (v21/*: any*/),
    (v26/*: any*/),
    (v57/*: any*/),
    (v54/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v60 = [
  (v43/*: any*/),
  (v49/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v59/*: any*/),
      (v8/*: any*/),
      (v19/*: any*/),
      (v20/*: any*/)
    ],
    "storageKey": null
  },
  (v12/*: any*/)
],
v61 = [
  (v3/*: any*/),
  (v9/*: any*/)
],
v62 = [
  (v43/*: any*/),
  (v49/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "assignee",
    "plural": false,
    "selections": [
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": (v61/*: any*/),
        "type": "User",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v61/*: any*/),
        "type": "Bot",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v61/*: any*/),
        "type": "Mannequin",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v61/*: any*/),
        "type": "Organization",
        "abstractKey": null
      },
      (v40/*: any*/)
    ],
    "storageKey": null
  },
  (v12/*: any*/)
],
v63 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v10/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v64 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v29/*: any*/),
    (v33/*: any*/),
    (v9/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v65 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v10/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v66 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v67 = [
  (v43/*: any*/),
  (v12/*: any*/),
  (v64/*: any*/)
],
v68 = {
  "kind": "InlineFragment",
  "selections": [
    (v55/*: any*/),
    (v58/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v69 = [
  (v12/*: any*/),
  (v43/*: any*/),
  (v64/*: any*/)
],
v70 = [
  (v12/*: any*/),
  (v43/*: any*/),
  (v64/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v10/*: any*/),
      (v3/*: any*/)
    ],
    "storageKey": null
  }
],
v71 = [
  (v12/*: any*/),
  (v64/*: any*/),
  (v43/*: any*/),
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
          (v17/*: any*/),
          (v10/*: any*/),
          (v18/*: any*/),
          (v21/*: any*/),
          (v26/*: any*/),
          (v57/*: any*/),
          (v25/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v40/*: any*/)
    ],
    "storageKey": null
  }
],
v72 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v53/*: any*/),
        (v10/*: any*/),
        (v22/*: any*/),
        (v54/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v56/*: any*/),
        (v10/*: any*/),
        (v21/*: any*/),
        (v26/*: any*/),
        (v57/*: any*/),
        (v54/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v73 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v74 = [
  (v68/*: any*/)
],
v75 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v76 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueTimelineItemsEdge",
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
            (v12/*: any*/)
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        (v40/*: any*/),
        (v41/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v27/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Issue",
              "kind": "LinkedField",
              "name": "issue",
              "plural": false,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "author",
                  "plural": false,
                  "selections": (v23/*: any*/),
                  "storageKey": null
                },
                (v3/*: any*/),
                (v18/*: any*/),
                (v28/*: any*/),
                (v12/*: any*/)
              ],
              "storageKey": null
            },
            (v3/*: any*/),
            (v30/*: any*/),
            {
              "alias": null,
              "args": [
                (v31/*: any*/)
              ],
              "kind": "ScalarField",
              "name": "bodyHTML",
              "storageKey": "bodyHTML(unfurlReferences:true)"
            },
            (v32/*: any*/),
            (v42/*: any*/),
            (v10/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "authorAssociation",
              "storageKey": null
            },
            (v35/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanMinimize",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanReport",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanReportToMaintainer",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanBlockFromOrg",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanUnblockFromOrg",
              "storageKey": null
            },
            {
              "alias": "isHidden",
              "args": null,
              "kind": "ScalarField",
              "name": "isMinimized",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "minimizedReason",
              "storageKey": null
            },
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
            {
              "alias": null,
              "args": null,
              "concreteType": "Sponsorship",
              "kind": "LinkedField",
              "name": "authorToRepoOwnerSponsorship",
              "plural": false,
              "selections": [
                (v43/*: any*/),
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
                (v9/*: any*/),
                (v44/*: any*/)
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
                (v8/*: any*/),
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
                    (v9/*: any*/),
                    (v10/*: any*/)
                  ],
                  "storageKey": null
                },
                (v11/*: any*/),
                (v13/*: any*/),
                (v7/*: any*/),
                (v12/*: any*/)
              ],
              "storageKey": null
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
                        (v10/*: any*/),
                        (v9/*: any*/),
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
                (v45/*: any*/),
                (v46/*: any*/)
              ]
            },
            (v48/*: any*/)
          ],
          "type": "IssueComment",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v49/*: any*/),
            (v12/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "willCloseSubject",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": (v50/*: any*/),
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": "Commit",
              "kind": "LinkedField",
              "name": "commit",
              "plural": false,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "message",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "messageHeadlineHTML",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "messageBodyHTML",
                  "storageKey": null
                },
                (v10/*: any*/),
                (v51/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "signature",
                  "plural": false,
                  "selections": [
                    (v2/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "User",
                      "kind": "LinkedField",
                      "name": "signer",
                      "plural": false,
                      "selections": [
                        (v9/*: any*/),
                        (v44/*: any*/),
                        (v3/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v21/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "wasSignedByGitHub",
                      "storageKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "issuer",
                          "plural": false,
                          "selections": (v52/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v52/*: any*/),
                          "storageKey": null
                        }
                      ],
                      "type": "SmimeSignature",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "keyId",
                          "storageKey": null
                        }
                      ],
                      "type": "GpgSignature",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "keyFingerprint",
                          "storageKey": null
                        }
                      ],
                      "type": "SshSignature",
                      "abstractKey": null
                    }
                  ],
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "verificationStatus",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasSignature",
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
                    (v24/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "defaultBranch",
                      "storageKey": null
                    },
                    (v3/*: any*/)
                  ],
                  "storageKey": null
                },
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v49/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "source",
              "plural": false,
              "selections": (v50/*: any*/),
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "willCloseTarget",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "referencedAt",
              "storageKey": null
            },
            (v12/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "target",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "Repository",
                      "kind": "LinkedField",
                      "name": "repository",
                      "plural": false,
                      "selections": (v16/*: any*/),
                      "storageKey": null
                    }
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v40/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": "innerSource",
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "source",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                {
                  "kind": "TypeDiscriminator",
                  "abstractKey": "__isReferencedSubject"
                },
                (v55/*: any*/),
                (v58/*: any*/),
                (v40/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v49/*: any*/),
            (v43/*: any*/),
            (v12/*: any*/)
          ],
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v60/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v60/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v62/*: any*/),
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v62/*: any*/),
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v49/*: any*/),
            (v12/*: any*/),
            (v63/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v49/*: any*/),
            (v63/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v64/*: any*/),
            (v65/*: any*/),
            (v66/*: any*/),
            (v12/*: any*/)
          ],
          "type": "AddedToProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v12/*: any*/),
            (v64/*: any*/),
            (v65/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "previousProjectColumnName",
              "storageKey": null
            },
            (v66/*: any*/)
          ],
          "type": "MovedColumnsInProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v12/*: any*/),
            (v64/*: any*/),
            (v65/*: any*/),
            (v66/*: any*/)
          ],
          "type": "RemovedFromProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v43/*: any*/),
            (v22/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                (v68/*: any*/),
                (v40/*: any*/)
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
                    (v10/*: any*/),
                    (v17/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v18/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v51/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v40/*: any*/)
              ],
              "storageKey": null
            },
            (v64/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v64/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v43/*: any*/),
            (v64/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "currentTitle",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "previousTitle",
              "storageKey": null
            }
          ],
          "type": "RenamedTitleEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v43/*: any*/),
            (v64/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "deletedCommentAuthor",
              "plural": false,
              "selections": (v23/*: any*/),
              "storageKey": null
            }
          ],
          "type": "CommentDeletedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v64/*: any*/),
            {
              "alias": "blockedUser",
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UserBlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v64/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v7/*: any*/),
                (v10/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "TransferredEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v64/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Project",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v10/*: any*/),
                (v8/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "ConvertedNoteToIssueEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v64/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v18/*: any*/),
                    (v72/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v18/*: any*/),
                    (v3/*: any*/),
                    (v72/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v40/*: any*/)
              ],
              "storageKey": null
            },
            (v73/*: any*/),
            (v12/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanUndo",
              "storageKey": null
            },
            (v3/*: any*/),
            {
              "kind": "ClientExtension",
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "pendingUndo",
                  "storageKey": null
                }
              ]
            }
          ],
          "type": "MarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v64/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v74/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v74/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v40/*: any*/)
              ],
              "storageKey": null
            },
            (v73/*: any*/),
            (v12/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v64/*: any*/),
            (v43/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v10/*: any*/),
                (v18/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "ConvertedToDiscussionEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v64/*: any*/),
            (v63/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "previousStatus",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "status",
              "storageKey": null
            }
          ],
          "type": "ProjectV2ItemStatusChangedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v43/*: any*/),
            (v64/*: any*/),
            (v12/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        }
      ],
      "storageKey": null
    },
    (v75/*: any*/)
  ],
  "storageKey": null
},
v77 = [
  "visibleEventsOnly"
],
v78 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v36/*: any*/)
],
v79 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
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
v80 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v39/*: any*/),
    (v38/*: any*/)
  ],
  "storageKey": null
},
v81 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v82 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v83 = {
  "alias": null,
  "args": (v15/*: any*/),
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
            (v3/*: any*/),
            (v6/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v3/*: any*/),
                (v17/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v42/*: any*/),
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": (v81/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v2/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v3/*: any*/),
                        (v8/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v3/*: any*/),
                            (v82/*: any*/),
                            (v8/*: any*/),
                            (v59/*: any*/),
                            (v19/*: any*/),
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
                    (v40/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v34/*: any*/),
                (v18/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v2/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v81/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v82/*: any*/),
                    (v8/*: any*/),
                    (v59/*: any*/),
                    (v19/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v40/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v2/*: any*/)
          ],
          "storageKey": null
        },
        (v75/*: any*/)
      ],
      "storageKey": null
    },
    (v80/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v84 = {
  "alias": null,
  "args": (v15/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v85 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v86 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v87 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v88 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v89 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v90 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v91 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v92 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v93 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v94 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v95 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v96 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v97 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v98 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v99 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v100 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v101 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v102 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
},
v103 = {
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
v104 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Sponsorship"
},
v105 = {
  "enumValues": [
    "ONE_DAY",
    "ONE_MONTH",
    "ONE_WEEK",
    "PERMANENT",
    "THREE_DAYS"
  ],
  "nullable": false,
  "plural": false,
  "type": "UserBlockDuration"
},
v106 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v107 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v108 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v109 = {
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
v110 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v111 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v112 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitSignature"
},
v113 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v114 = {
  "enumValues": [
    "BAD_CERT",
    "BAD_EMAIL",
    "EXPIRED_KEY",
    "GPGVERIFY_ERROR",
    "GPGVERIFY_UNAVAILABLE",
    "INVALID",
    "MALFORMED_SIG",
    "NOT_SIGNING_KEY",
    "NO_USER",
    "OCSP_ERROR",
    "OCSP_PENDING",
    "OCSP_REVOKED",
    "UNKNOWN_KEY",
    "UNKNOWN_SIG_TYPE",
    "UNSIGNED",
    "UNVERIFIED_EMAIL",
    "VALID"
  ],
  "nullable": false,
  "plural": false,
  "type": "GitSignatureState"
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
  "type": "Discussion"
},
v117 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v118 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v119 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v120 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v121 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v122 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v123 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v124 = {
  "enumValues": [
    "OFF_TOPIC",
    "RESOLVED",
    "SPAM",
    "TOO_HEATED"
  ],
  "nullable": true,
  "plural": false,
  "type": "LockReason"
},
v125 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
},
v126 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "ProjectV2"
},
v127 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "ReactionGroup"
},
v128 = {
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
v129 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReactorConnection"
},
v130 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Reactor"
},
v131 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v132 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v133 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v134 = {
  "enumValues": (v133/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "ProjectV2SingleSelectFieldOptionColor"
},
v135 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueViewerTestComponentQuery",
    "selections": [
      {
        "alias": "issue",
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
                  {
                    "kind": "Literal",
                    "name": "useNewTimeline",
                    "value": false
                  }
                ],
                "kind": "FragmentSpread",
                "name": "IssueViewerIssue"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"mockIssueId1\")"
      },
      {
        "alias": "viewer",
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
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueViewerViewer"
              }
            ],
            "type": "User",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id-viewer\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueViewerTestComponentQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v0/*: any*/),
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
                "name": "updatedAt",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "resourcePath",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "canBeSummarized",
                "storageKey": null
              },
              {
                "alias": "subIssuesConnection",
                "args": null,
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "subIssues",
                "plural": false,
                "selections": (v5/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateMetadata",
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
                  (v3/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v9/*: any*/),
                      (v3/*: any*/),
                      (v10/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v11/*: any*/),
                  (v12/*: any*/),
                  (v13/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanInteract",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerInteractionLimitReasonHTML",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "RepositoryPlanFeatures",
                    "kind": "LinkedField",
                    "name": "planFeatures",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "maximumAssignees",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": [
                      {
                        "kind": "Literal",
                        "name": "first",
                        "value": 3
                      }
                    ],
                    "concreteType": "PinnedIssueConnection",
                    "kind": "LinkedField",
                    "name": "pinnedIssues",
                    "plural": false,
                    "selections": (v5/*: any*/),
                    "storageKey": "pinnedIssues(first:3)"
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanPinIssues",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": (v15/*: any*/),
                    "concreteType": "IssueTypeConnection",
                    "kind": "LinkedField",
                    "name": "issueTypes",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "IssueTypeEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "IssueType",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": (v16/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "issueTypes(first:10)"
                  }
                ],
                "storageKey": null
              },
              (v17/*: any*/),
              (v18/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "titleHTML",
                "storageKey": null
              },
              (v10/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateNext",
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
                  (v8/*: any*/),
                  (v19/*: any*/),
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isEnabled",
                    "storageKey": null
                  },
                  (v20/*: any*/)
                ],
                "storageKey": null
              },
              (v21/*: any*/),
              (v22/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v18/*: any*/),
                  (v10/*: any*/),
                  (v25/*: any*/),
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v14/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "includeClosedPrs",
                    "value": false
                  },
                  {
                    "kind": "Literal",
                    "name": "orderByState",
                    "value": true
                  }
                ],
                "concreteType": "PullRequestConnection",
                "kind": "LinkedField",
                "name": "closedByPullRequestsReferences",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PullRequest",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v7/*: any*/),
                          (v3/*: any*/),
                          (v8/*: any*/),
                          (v24/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v21/*: any*/),
                      (v26/*: any*/),
                      (v10/*: any*/),
                      (v18/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "closedByPullRequestsReferences(first:10,includeClosedPrs:false,orderByState:true)"
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "SubIssuesSummary",
                "kind": "LinkedField",
                "name": "subIssuesSummary",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "completed",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v12/*: any*/),
              (v27/*: any*/),
              (v28/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v29/*: any*/),
                  (v9/*: any*/),
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              (v30/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v31/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v32/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": (v16/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanComment",
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 20
                  }
                ],
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "User",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v3/*: any*/),
                      (v9/*: any*/),
                      (v8/*: any*/),
                      (v33/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "assignees(first:20)"
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
                "kind": "ScalarField",
                "name": "viewerCanLabel",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": [
                  (v3/*: any*/),
                  (v17/*: any*/),
                  (v34/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "dueOn",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "progressPercentage",
                    "storageKey": null
                  },
                  (v10/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "closedAt",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanSetMilestone",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isPinned",
                "storageKey": null
              },
              (v35/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanTransfer",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanConvertToDiscussion",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanLock",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanType",
                "storageKey": null
              },
              {
                "alias": "frontTimeline",
                "args": (v37/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PageInfo",
                    "kind": "LinkedField",
                    "name": "pageInfo",
                    "plural": false,
                    "selections": [
                      (v38/*: any*/),
                      (v39/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v76/*: any*/),
                  (v41/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimeline",
                "args": (v37/*: any*/),
                "filters": (v77/*: any*/),
                "handle": "connection",
                "key": "Issue_frontTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": null,
                "args": (v78/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
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
                  (v76/*: any*/),
                  (v41/*: any*/)
                ],
                "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
              },
              {
                "alias": null,
                "args": (v78/*: any*/),
                "filters": (v77/*: any*/),
                "handle": "connection",
                "key": "IssueBacksideTimeline_timelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
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
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "subIssues",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Issue",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v34/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "subIssues(first:50)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v43/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "author",
                    "plural": false,
                    "selections": [
                      (v44/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "profileUrl",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v48/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v45/*: any*/),
                  (v46/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v79/*: any*/),
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
                              (v3/*: any*/),
                              (v19/*: any*/),
                              (v8/*: any*/),
                              (v59/*: any*/),
                              (v20/*: any*/),
                              (v10/*: any*/),
                              (v2/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v75/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v80/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v79/*: any*/),
                    "filters": [
                      "orderBy"
                    ],
                    "handle": "connection",
                    "key": "MetadataSectionAssignedLabels_labels",
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
                      (v83/*: any*/),
                      (v84/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v83/*: any*/),
                      (v84/*: any*/),
                      (v42/*: any*/)
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
        "storageKey": "node(id:\"mockIssueId1\")"
      },
      {
        "alias": "viewer",
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
                "name": "isEnterpriseManagedUser",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "enterpriseManagedEnterpriseId",
                "storageKey": null
              },
              (v9/*: any*/),
              (v33/*: any*/),
              (v8/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isEmployee",
                "storageKey": null
              }
            ],
            "type": "User",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id-viewer\")"
      }
    ]
  },
  "params": {
    "id": "e35babb2f82d6fd31c3719e60541e170",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": (v85/*: any*/),
        "issue.__isComment": (v86/*: any*/),
        "issue.__isIssueOrPullRequest": (v86/*: any*/),
        "issue.__isLabelable": (v86/*: any*/),
        "issue.__isNode": (v86/*: any*/),
        "issue.__isReactable": (v86/*: any*/),
        "issue.__typename": (v86/*: any*/),
        "issue.assignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "UserConnection"
        },
        "issue.assignees.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "issue.assignees.nodes.avatarUrl": (v87/*: any*/),
        "issue.assignees.nodes.id": (v88/*: any*/),
        "issue.assignees.nodes.login": (v86/*: any*/),
        "issue.assignees.nodes.name": (v89/*: any*/),
        "issue.author": (v90/*: any*/),
        "issue.author.__isActor": (v86/*: any*/),
        "issue.author.__typename": (v86/*: any*/),
        "issue.author.avatarUrl": (v87/*: any*/),
        "issue.author.id": (v88/*: any*/),
        "issue.author.login": (v86/*: any*/),
        "issue.author.profileUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "issue.body": (v86/*: any*/),
        "issue.bodyHTML": (v91/*: any*/),
        "issue.bodyVersion": (v86/*: any*/),
        "issue.canBeSummarized": (v92/*: any*/),
        "issue.createdAt": (v93/*: any*/),
        "issue.databaseId": (v94/*: any*/),
        "issue.duplicateOf": (v95/*: any*/),
        "issue.duplicateOf.id": (v88/*: any*/),
        "issue.duplicateOf.number": (v96/*: any*/),
        "issue.duplicateOf.repository": (v97/*: any*/),
        "issue.duplicateOf.repository.id": (v88/*: any*/),
        "issue.duplicateOf.repository.name": (v86/*: any*/),
        "issue.duplicateOf.repository.owner": (v98/*: any*/),
        "issue.duplicateOf.repository.owner.__typename": (v86/*: any*/),
        "issue.duplicateOf.repository.owner.id": (v88/*: any*/),
        "issue.duplicateOf.repository.owner.login": (v86/*: any*/),
        "issue.duplicateOf.url": (v87/*: any*/),
        "issue.frontTimeline": (v99/*: any*/),
        "issue.frontTimeline.__id": (v88/*: any*/),
        "issue.frontTimeline.edges": (v100/*: any*/),
        "issue.frontTimeline.edges.cursor": (v86/*: any*/),
        "issue.frontTimeline.edges.node": (v101/*: any*/),
        "issue.frontTimeline.edges.node.__id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.__isComment": (v86/*: any*/),
        "issue.frontTimeline.edges.node.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.__isReactable": (v86/*: any*/),
        "issue.frontTimeline.edges.node.__isTimelineEvent": (v86/*: any*/),
        "issue.frontTimeline.edges.node.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.actor": (v90/*: any*/),
        "issue.frontTimeline.edges.node.actor.__isActor": (v86/*: any*/),
        "issue.frontTimeline.edges.node.actor.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.actor.avatarUrl": (v87/*: any*/),
        "issue.frontTimeline.edges.node.actor.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.actor.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.assignee": (v102/*: any*/),
        "issue.frontTimeline.edges.node.assignee.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.assignee.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.assignee.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.assignee.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.author": (v90/*: any*/),
        "issue.frontTimeline.edges.node.author.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.author.avatarUrl": (v87/*: any*/),
        "issue.frontTimeline.edges.node.author.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.author.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.authorAssociation": (v103/*: any*/),
        "issue.frontTimeline.edges.node.authorToRepoOwnerSponsorship": (v104/*: any*/),
        "issue.frontTimeline.edges.node.authorToRepoOwnerSponsorship.createdAt": (v93/*: any*/),
        "issue.frontTimeline.edges.node.authorToRepoOwnerSponsorship.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.authorToRepoOwnerSponsorship.isActive": (v92/*: any*/),
        "issue.frontTimeline.edges.node.blockDuration": (v105/*: any*/),
        "issue.frontTimeline.edges.node.blockedUser": (v106/*: any*/),
        "issue.frontTimeline.edges.node.blockedUser.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.blockedUser.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.body": (v86/*: any*/),
        "issue.frontTimeline.edges.node.bodyHTML": (v91/*: any*/),
        "issue.frontTimeline.edges.node.bodyVersion": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical": (v107/*: any*/),
        "issue.frontTimeline.edges.node.canonical.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.__isReferencedSubject": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.canonical.isDraft": (v92/*: any*/),
        "issue.frontTimeline.edges.node.canonical.isInMergeQueue": (v92/*: any*/),
        "issue.frontTimeline.edges.node.canonical.issueTitleHTML": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.canonical.pullTitleHTML": (v91/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.isPrivate": (v92/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.canonical.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.canonical.state": (v108/*: any*/),
        "issue.frontTimeline.edges.node.canonical.stateReason": (v109/*: any*/),
        "issue.frontTimeline.edges.node.canonical.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.closer": (v110/*: any*/),
        "issue.frontTimeline.edges.node.closer.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.abbreviatedOid": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.closer.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.closer.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.title": (v86/*: any*/),
        "issue.frontTimeline.edges.node.closer.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.closingProjectItemStatus": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit": (v111/*: any*/),
        "issue.frontTimeline.edges.node.commit.abbreviatedOid": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.hasSignature": (v92/*: any*/),
        "issue.frontTimeline.edges.node.commit.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.commit.message": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.messageBodyHTML": (v91/*: any*/),
        "issue.frontTimeline.edges.node.commit.messageHeadlineHTML": (v91/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.defaultBranch": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.commit.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature": (v112/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.issuer": (v113/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.issuer.commonName": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.issuer.emailAddress": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.issuer.organization": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.issuer.organizationUnit": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.keyFingerprint": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.keyId": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.signer": (v106/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.signer.avatarUrl": (v87/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.signer.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.signer.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.state": (v114/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.subject": (v113/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.subject.commonName": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.subject.emailAddress": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.subject.organization": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.subject.organizationUnit": (v89/*: any*/),
        "issue.frontTimeline.edges.node.commit.signature.wasSignedByGitHub": (v92/*: any*/),
        "issue.frontTimeline.edges.node.commit.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.commit.verificationStatus": (v115/*: any*/),
        "issue.frontTimeline.edges.node.createdAt": (v93/*: any*/),
        "issue.frontTimeline.edges.node.createdViaEmail": (v92/*: any*/),
        "issue.frontTimeline.edges.node.currentTitle": (v86/*: any*/),
        "issue.frontTimeline.edges.node.databaseId": (v94/*: any*/),
        "issue.frontTimeline.edges.node.deletedCommentAuthor": (v90/*: any*/),
        "issue.frontTimeline.edges.node.deletedCommentAuthor.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.deletedCommentAuthor.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.deletedCommentAuthor.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.discussion": (v116/*: any*/),
        "issue.frontTimeline.edges.node.discussion.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.discussion.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.discussion.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf": (v107/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.__isReferencedSubject": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.isDraft": (v92/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.isInMergeQueue": (v92/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.issueTitleHTML": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.pullTitleHTML": (v91/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.isPrivate": (v92/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.state": (v108/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.stateReason": (v109/*: any*/),
        "issue.frontTimeline.edges.node.duplicateOf.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.fromRepository": (v117/*: any*/),
        "issue.frontTimeline.edges.node.fromRepository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.fromRepository.nameWithOwner": (v86/*: any*/),
        "issue.frontTimeline.edges.node.fromRepository.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.innerSource": (v118/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.__isReferencedSubject": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.isDraft": (v92/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.isInMergeQueue": (v92/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.issueTitleHTML": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.pullTitleHTML": (v91/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.isPrivate": (v92/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.state": (v108/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.stateReason": (v109/*: any*/),
        "issue.frontTimeline.edges.node.innerSource.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.isCanonicalOfClosedDuplicate": (v119/*: any*/),
        "issue.frontTimeline.edges.node.isHidden": (v92/*: any*/),
        "issue.frontTimeline.edges.node.issue": (v120/*: any*/),
        "issue.frontTimeline.edges.node.issue.author": (v90/*: any*/),
        "issue.frontTimeline.edges.node.issue.author.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.issue.author.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.issue.author.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.issue.databaseId": (v94/*: any*/),
        "issue.frontTimeline.edges.node.issue.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.issue.locked": (v92/*: any*/),
        "issue.frontTimeline.edges.node.issue.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.label": (v121/*: any*/),
        "issue.frontTimeline.edges.node.label.color": (v86/*: any*/),
        "issue.frontTimeline.edges.node.label.description": (v89/*: any*/),
        "issue.frontTimeline.edges.node.label.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.label.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.label.nameHTML": (v86/*: any*/),
        "issue.frontTimeline.edges.node.lastEditedAt": (v122/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit": (v123/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit.editor": (v90/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit.editor.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit.editor.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit.editor.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit.editor.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.lastUserContentEdit.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.lockReason": (v124/*: any*/),
        "issue.frontTimeline.edges.node.milestone": (v125/*: any*/),
        "issue.frontTimeline.edges.node.milestone.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.milestone.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.milestoneTitle": (v86/*: any*/),
        "issue.frontTimeline.edges.node.minimizedReason": (v89/*: any*/),
        "issue.frontTimeline.edges.node.pendingBlock": (v119/*: any*/),
        "issue.frontTimeline.edges.node.pendingMinimizeReason": (v89/*: any*/),
        "issue.frontTimeline.edges.node.pendingUnblock": (v119/*: any*/),
        "issue.frontTimeline.edges.node.pendingUndo": (v119/*: any*/),
        "issue.frontTimeline.edges.node.previousProjectColumnName": (v86/*: any*/),
        "issue.frontTimeline.edges.node.previousStatus": (v86/*: any*/),
        "issue.frontTimeline.edges.node.previousTitle": (v86/*: any*/),
        "issue.frontTimeline.edges.node.project": (v126/*: any*/),
        "issue.frontTimeline.edges.node.project.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.project.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.project.title": (v86/*: any*/),
        "issue.frontTimeline.edges.node.project.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.projectColumnName": (v86/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups": (v127/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.content": (v128/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors": (v129/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors.nodes": (v130/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors.nodes.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors.nodes.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors.nodes.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors.nodes.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.reactors.totalCount": (v96/*: any*/),
        "issue.frontTimeline.edges.node.reactionGroups.viewerHasReacted": (v92/*: any*/),
        "issue.frontTimeline.edges.node.referencedAt": (v93/*: any*/),
        "issue.frontTimeline.edges.node.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.repository.databaseId": (v94/*: any*/),
        "issue.frontTimeline.edges.node.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.repository.isPrivate": (v92/*: any*/),
        "issue.frontTimeline.edges.node.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.repository.nameWithOwner": (v86/*: any*/),
        "issue.frontTimeline.edges.node.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.repository.owner.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.repository.slashCommandsEnabled": (v92/*: any*/),
        "issue.frontTimeline.edges.node.showSpammyBadge": (v92/*: any*/),
        "issue.frontTimeline.edges.node.source": (v118/*: any*/),
        "issue.frontTimeline.edges.node.source.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.source.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.source.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.stateReason": (v109/*: any*/),
        "issue.frontTimeline.edges.node.status": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject": (v118/*: any*/),
        "issue.frontTimeline.edges.node.subject.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.subject.isDraft": (v92/*: any*/),
        "issue.frontTimeline.edges.node.subject.isInMergeQueue": (v92/*: any*/),
        "issue.frontTimeline.edges.node.subject.number": (v96/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository.name": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository.owner": (v98/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository.owner.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository.owner.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.subject.repository.owner.login": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject.state": (v108/*: any*/),
        "issue.frontTimeline.edges.node.subject.title": (v86/*: any*/),
        "issue.frontTimeline.edges.node.subject.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.target": (v118/*: any*/),
        "issue.frontTimeline.edges.node.target.__isNode": (v86/*: any*/),
        "issue.frontTimeline.edges.node.target.__typename": (v86/*: any*/),
        "issue.frontTimeline.edges.node.target.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.target.repository": (v97/*: any*/),
        "issue.frontTimeline.edges.node.target.repository.id": (v88/*: any*/),
        "issue.frontTimeline.edges.node.url": (v87/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanBlockFromOrg": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanDelete": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanMinimize": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanReadUserContentEdits": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanReport": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanReportToMaintainer": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanUnblockFromOrg": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanUndo": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerCanUpdate": (v92/*: any*/),
        "issue.frontTimeline.edges.node.viewerDidAuthor": (v92/*: any*/),
        "issue.frontTimeline.edges.node.willCloseSubject": (v92/*: any*/),
        "issue.frontTimeline.edges.node.willCloseTarget": (v92/*: any*/),
        "issue.frontTimeline.pageInfo": (v131/*: any*/),
        "issue.frontTimeline.pageInfo.endCursor": (v89/*: any*/),
        "issue.frontTimeline.pageInfo.hasNextPage": (v92/*: any*/),
        "issue.frontTimeline.totalCount": (v96/*: any*/),
        "issue.id": (v88/*: any*/),
        "issue.isPinned": (v119/*: any*/),
        "issue.issueType": (v132/*: any*/),
        "issue.issueType.color": {
          "enumValues": (v133/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueTypeColor"
        },
        "issue.issueType.description": (v89/*: any*/),
        "issue.issueType.id": (v88/*: any*/),
        "issue.issueType.isEnabled": (v92/*: any*/),
        "issue.issueType.name": (v86/*: any*/),
        "issue.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "issue.labels.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LabelEdge"
        },
        "issue.labels.edges.cursor": (v86/*: any*/),
        "issue.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "issue.labels.edges.node.__typename": (v86/*: any*/),
        "issue.labels.edges.node.color": (v86/*: any*/),
        "issue.labels.edges.node.description": (v89/*: any*/),
        "issue.labels.edges.node.id": (v88/*: any*/),
        "issue.labels.edges.node.name": (v86/*: any*/),
        "issue.labels.edges.node.nameHTML": (v86/*: any*/),
        "issue.labels.edges.node.url": (v87/*: any*/),
        "issue.labels.pageInfo": (v131/*: any*/),
        "issue.labels.pageInfo.endCursor": (v89/*: any*/),
        "issue.labels.pageInfo.hasNextPage": (v92/*: any*/),
        "issue.linkedPullRequests": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestConnection"
        },
        "issue.linkedPullRequests.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequest"
        },
        "issue.linkedPullRequests.nodes.id": (v88/*: any*/),
        "issue.linkedPullRequests.nodes.isDraft": (v92/*: any*/),
        "issue.linkedPullRequests.nodes.number": (v96/*: any*/),
        "issue.linkedPullRequests.nodes.repository": (v97/*: any*/),
        "issue.linkedPullRequests.nodes.repository.id": (v88/*: any*/),
        "issue.linkedPullRequests.nodes.repository.name": (v86/*: any*/),
        "issue.linkedPullRequests.nodes.repository.nameWithOwner": (v86/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner": (v98/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.__typename": (v86/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.id": (v88/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.login": (v86/*: any*/),
        "issue.linkedPullRequests.nodes.state": (v108/*: any*/),
        "issue.linkedPullRequests.nodes.url": (v87/*: any*/),
        "issue.locked": (v92/*: any*/),
        "issue.milestone": (v125/*: any*/),
        "issue.milestone.closed": (v92/*: any*/),
        "issue.milestone.closedAt": (v122/*: any*/),
        "issue.milestone.dueOn": (v122/*: any*/),
        "issue.milestone.id": (v88/*: any*/),
        "issue.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "issue.milestone.title": (v86/*: any*/),
        "issue.milestone.url": (v87/*: any*/),
        "issue.number": (v96/*: any*/),
        "issue.parent": (v95/*: any*/),
        "issue.parent.id": (v88/*: any*/),
        "issue.pendingBlock": (v119/*: any*/),
        "issue.pendingUnblock": (v119/*: any*/),
        "issue.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "issue.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "issue.projectItemsNext.edges.cursor": (v86/*: any*/),
        "issue.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "issue.projectItemsNext.edges.node.__typename": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "issue.projectItemsNext.edges.node.fieldValueByName.__isNode": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.__typename": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.color": (v134/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.id": (v88/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.name": (v89/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v89/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.optionId": (v89/*: any*/),
        "issue.projectItemsNext.edges.node.id": (v88/*: any*/),
        "issue.projectItemsNext.edges.node.isArchived": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "issue.projectItemsNext.edges.node.project.__typename": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.closed": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "issue.projectItemsNext.edges.node.project.field.__isNode": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.__typename": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.id": (v88/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.name": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "issue.projectItemsNext.edges.node.project.field.options.color": (v134/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.description": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.id": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.name": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.nameHTML": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.optionId": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.id": (v88/*: any*/),
        "issue.projectItemsNext.edges.node.project.number": (v96/*: any*/),
        "issue.projectItemsNext.edges.node.project.template": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.title": (v86/*: any*/),
        "issue.projectItemsNext.edges.node.project.url": (v87/*: any*/),
        "issue.projectItemsNext.edges.node.project.viewerCanUpdate": (v92/*: any*/),
        "issue.projectItemsNext.pageInfo": (v131/*: any*/),
        "issue.projectItemsNext.pageInfo.endCursor": (v89/*: any*/),
        "issue.projectItemsNext.pageInfo.hasNextPage": (v92/*: any*/),
        "issue.reactionGroups": (v127/*: any*/),
        "issue.reactionGroups.content": (v128/*: any*/),
        "issue.reactionGroups.reactors": (v129/*: any*/),
        "issue.reactionGroups.reactors.nodes": (v130/*: any*/),
        "issue.reactionGroups.reactors.nodes.__isNode": (v86/*: any*/),
        "issue.reactionGroups.reactors.nodes.__typename": (v86/*: any*/),
        "issue.reactionGroups.reactors.nodes.id": (v88/*: any*/),
        "issue.reactionGroups.reactors.nodes.login": (v86/*: any*/),
        "issue.reactionGroups.reactors.totalCount": (v96/*: any*/),
        "issue.reactionGroups.viewerHasReacted": (v92/*: any*/),
        "issue.repository": (v97/*: any*/),
        "issue.repository.databaseId": (v94/*: any*/),
        "issue.repository.id": (v88/*: any*/),
        "issue.repository.isArchived": (v92/*: any*/),
        "issue.repository.isPrivate": (v92/*: any*/),
        "issue.repository.issueTypes": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueTypeConnection"
        },
        "issue.repository.issueTypes.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTypeEdge"
        },
        "issue.repository.issueTypes.edges.node": (v132/*: any*/),
        "issue.repository.issueTypes.edges.node.id": (v88/*: any*/),
        "issue.repository.name": (v86/*: any*/),
        "issue.repository.nameWithOwner": (v86/*: any*/),
        "issue.repository.owner": (v98/*: any*/),
        "issue.repository.owner.__typename": (v86/*: any*/),
        "issue.repository.owner.id": (v88/*: any*/),
        "issue.repository.owner.login": (v86/*: any*/),
        "issue.repository.owner.url": (v87/*: any*/),
        "issue.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "issue.repository.pinnedIssues.totalCount": (v96/*: any*/),
        "issue.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "issue.repository.planFeatures.maximumAssignees": (v96/*: any*/),
        "issue.repository.slashCommandsEnabled": (v92/*: any*/),
        "issue.repository.viewerCanInteract": (v92/*: any*/),
        "issue.repository.viewerCanPinIssues": (v92/*: any*/),
        "issue.repository.viewerInteractionLimitReasonHTML": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "HTML"
        },
        "issue.resourcePath": (v87/*: any*/),
        "issue.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "issue.stateReason": (v109/*: any*/),
        "issue.subIssues": (v135/*: any*/),
        "issue.subIssues.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Issue"
        },
        "issue.subIssues.nodes.closed": (v92/*: any*/),
        "issue.subIssues.nodes.id": (v88/*: any*/),
        "issue.subIssuesConnection": (v135/*: any*/),
        "issue.subIssuesConnection.totalCount": (v96/*: any*/),
        "issue.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "issue.subIssuesSummary.completed": (v96/*: any*/),
        "issue.timelineItems": (v99/*: any*/),
        "issue.timelineItems.__id": (v88/*: any*/),
        "issue.timelineItems.edges": (v100/*: any*/),
        "issue.timelineItems.edges.cursor": (v86/*: any*/),
        "issue.timelineItems.edges.node": (v101/*: any*/),
        "issue.timelineItems.edges.node.__id": (v88/*: any*/),
        "issue.timelineItems.edges.node.__isComment": (v86/*: any*/),
        "issue.timelineItems.edges.node.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.__isReactable": (v86/*: any*/),
        "issue.timelineItems.edges.node.__isTimelineEvent": (v86/*: any*/),
        "issue.timelineItems.edges.node.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.actor": (v90/*: any*/),
        "issue.timelineItems.edges.node.actor.__isActor": (v86/*: any*/),
        "issue.timelineItems.edges.node.actor.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.actor.avatarUrl": (v87/*: any*/),
        "issue.timelineItems.edges.node.actor.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.actor.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.assignee": (v102/*: any*/),
        "issue.timelineItems.edges.node.assignee.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.assignee.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.assignee.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.assignee.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.author": (v90/*: any*/),
        "issue.timelineItems.edges.node.author.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.author.avatarUrl": (v87/*: any*/),
        "issue.timelineItems.edges.node.author.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.author.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.authorAssociation": (v103/*: any*/),
        "issue.timelineItems.edges.node.authorToRepoOwnerSponsorship": (v104/*: any*/),
        "issue.timelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v93/*: any*/),
        "issue.timelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v92/*: any*/),
        "issue.timelineItems.edges.node.blockDuration": (v105/*: any*/),
        "issue.timelineItems.edges.node.blockedUser": (v106/*: any*/),
        "issue.timelineItems.edges.node.blockedUser.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.blockedUser.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.body": (v86/*: any*/),
        "issue.timelineItems.edges.node.bodyHTML": (v91/*: any*/),
        "issue.timelineItems.edges.node.bodyVersion": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical": (v107/*: any*/),
        "issue.timelineItems.edges.node.canonical.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.__isReferencedSubject": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.canonical.isDraft": (v92/*: any*/),
        "issue.timelineItems.edges.node.canonical.isInMergeQueue": (v92/*: any*/),
        "issue.timelineItems.edges.node.canonical.issueTitleHTML": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.canonical.pullTitleHTML": (v91/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.isPrivate": (v92/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.canonical.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.canonical.state": (v108/*: any*/),
        "issue.timelineItems.edges.node.canonical.stateReason": (v109/*: any*/),
        "issue.timelineItems.edges.node.canonical.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.closer": (v110/*: any*/),
        "issue.timelineItems.edges.node.closer.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.abbreviatedOid": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.closer.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.closer.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.closer.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.closer.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.closer.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.closer.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.title": (v86/*: any*/),
        "issue.timelineItems.edges.node.closer.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.closingProjectItemStatus": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit": (v111/*: any*/),
        "issue.timelineItems.edges.node.commit.abbreviatedOid": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.hasSignature": (v92/*: any*/),
        "issue.timelineItems.edges.node.commit.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.commit.message": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.messageBodyHTML": (v91/*: any*/),
        "issue.timelineItems.edges.node.commit.messageHeadlineHTML": (v91/*: any*/),
        "issue.timelineItems.edges.node.commit.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.defaultBranch": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.commit.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.signature": (v112/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.issuer": (v113/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.issuer.commonName": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.issuer.emailAddress": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.issuer.organization": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.issuer.organizationUnit": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.keyFingerprint": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.keyId": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.signer": (v106/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.signer.avatarUrl": (v87/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.signer.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.signer.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.state": (v114/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.subject": (v113/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.subject.commonName": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.subject.emailAddress": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.subject.organization": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.subject.organizationUnit": (v89/*: any*/),
        "issue.timelineItems.edges.node.commit.signature.wasSignedByGitHub": (v92/*: any*/),
        "issue.timelineItems.edges.node.commit.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.commit.verificationStatus": (v115/*: any*/),
        "issue.timelineItems.edges.node.createdAt": (v93/*: any*/),
        "issue.timelineItems.edges.node.createdViaEmail": (v92/*: any*/),
        "issue.timelineItems.edges.node.currentTitle": (v86/*: any*/),
        "issue.timelineItems.edges.node.databaseId": (v94/*: any*/),
        "issue.timelineItems.edges.node.deletedCommentAuthor": (v90/*: any*/),
        "issue.timelineItems.edges.node.deletedCommentAuthor.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.deletedCommentAuthor.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.deletedCommentAuthor.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.discussion": (v116/*: any*/),
        "issue.timelineItems.edges.node.discussion.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.discussion.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.discussion.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf": (v107/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.__isReferencedSubject": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.isDraft": (v92/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.isInMergeQueue": (v92/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.issueTitleHTML": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.pullTitleHTML": (v91/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.isPrivate": (v92/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.state": (v108/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.stateReason": (v109/*: any*/),
        "issue.timelineItems.edges.node.duplicateOf.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.fromRepository": (v117/*: any*/),
        "issue.timelineItems.edges.node.fromRepository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.fromRepository.nameWithOwner": (v86/*: any*/),
        "issue.timelineItems.edges.node.fromRepository.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.innerSource": (v118/*: any*/),
        "issue.timelineItems.edges.node.innerSource.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.__isReferencedSubject": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.innerSource.isDraft": (v92/*: any*/),
        "issue.timelineItems.edges.node.innerSource.isInMergeQueue": (v92/*: any*/),
        "issue.timelineItems.edges.node.innerSource.issueTitleHTML": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.innerSource.pullTitleHTML": (v91/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.isPrivate": (v92/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.innerSource.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.innerSource.state": (v108/*: any*/),
        "issue.timelineItems.edges.node.innerSource.stateReason": (v109/*: any*/),
        "issue.timelineItems.edges.node.innerSource.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.isCanonicalOfClosedDuplicate": (v119/*: any*/),
        "issue.timelineItems.edges.node.isHidden": (v92/*: any*/),
        "issue.timelineItems.edges.node.issue": (v120/*: any*/),
        "issue.timelineItems.edges.node.issue.author": (v90/*: any*/),
        "issue.timelineItems.edges.node.issue.author.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.issue.author.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.issue.author.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.issue.databaseId": (v94/*: any*/),
        "issue.timelineItems.edges.node.issue.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.issue.locked": (v92/*: any*/),
        "issue.timelineItems.edges.node.issue.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.label": (v121/*: any*/),
        "issue.timelineItems.edges.node.label.color": (v86/*: any*/),
        "issue.timelineItems.edges.node.label.description": (v89/*: any*/),
        "issue.timelineItems.edges.node.label.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.label.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.label.nameHTML": (v86/*: any*/),
        "issue.timelineItems.edges.node.lastEditedAt": (v122/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit": (v123/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit.editor": (v90/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit.editor.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit.editor.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit.editor.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit.editor.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.lastUserContentEdit.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.lockReason": (v124/*: any*/),
        "issue.timelineItems.edges.node.milestone": (v125/*: any*/),
        "issue.timelineItems.edges.node.milestone.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.milestone.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.milestoneTitle": (v86/*: any*/),
        "issue.timelineItems.edges.node.minimizedReason": (v89/*: any*/),
        "issue.timelineItems.edges.node.pendingBlock": (v119/*: any*/),
        "issue.timelineItems.edges.node.pendingMinimizeReason": (v89/*: any*/),
        "issue.timelineItems.edges.node.pendingUnblock": (v119/*: any*/),
        "issue.timelineItems.edges.node.pendingUndo": (v119/*: any*/),
        "issue.timelineItems.edges.node.previousProjectColumnName": (v86/*: any*/),
        "issue.timelineItems.edges.node.previousStatus": (v86/*: any*/),
        "issue.timelineItems.edges.node.previousTitle": (v86/*: any*/),
        "issue.timelineItems.edges.node.project": (v126/*: any*/),
        "issue.timelineItems.edges.node.project.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.project.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.project.title": (v86/*: any*/),
        "issue.timelineItems.edges.node.project.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.projectColumnName": (v86/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups": (v127/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.content": (v128/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors": (v129/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors.nodes": (v130/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors.nodes.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors.nodes.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.reactors.totalCount": (v96/*: any*/),
        "issue.timelineItems.edges.node.reactionGroups.viewerHasReacted": (v92/*: any*/),
        "issue.timelineItems.edges.node.referencedAt": (v93/*: any*/),
        "issue.timelineItems.edges.node.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.repository.databaseId": (v94/*: any*/),
        "issue.timelineItems.edges.node.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.repository.isPrivate": (v92/*: any*/),
        "issue.timelineItems.edges.node.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.repository.nameWithOwner": (v86/*: any*/),
        "issue.timelineItems.edges.node.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.repository.owner.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.repository.slashCommandsEnabled": (v92/*: any*/),
        "issue.timelineItems.edges.node.showSpammyBadge": (v92/*: any*/),
        "issue.timelineItems.edges.node.source": (v118/*: any*/),
        "issue.timelineItems.edges.node.source.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.source.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.source.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.stateReason": (v109/*: any*/),
        "issue.timelineItems.edges.node.status": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject": (v118/*: any*/),
        "issue.timelineItems.edges.node.subject.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.subject.isDraft": (v92/*: any*/),
        "issue.timelineItems.edges.node.subject.isInMergeQueue": (v92/*: any*/),
        "issue.timelineItems.edges.node.subject.number": (v96/*: any*/),
        "issue.timelineItems.edges.node.subject.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.subject.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.subject.repository.name": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject.repository.owner": (v98/*: any*/),
        "issue.timelineItems.edges.node.subject.repository.owner.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject.repository.owner.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.subject.repository.owner.login": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject.state": (v108/*: any*/),
        "issue.timelineItems.edges.node.subject.title": (v86/*: any*/),
        "issue.timelineItems.edges.node.subject.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.target": (v118/*: any*/),
        "issue.timelineItems.edges.node.target.__isNode": (v86/*: any*/),
        "issue.timelineItems.edges.node.target.__typename": (v86/*: any*/),
        "issue.timelineItems.edges.node.target.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.target.repository": (v97/*: any*/),
        "issue.timelineItems.edges.node.target.repository.id": (v88/*: any*/),
        "issue.timelineItems.edges.node.url": (v87/*: any*/),
        "issue.timelineItems.edges.node.viewerCanBlockFromOrg": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanDelete": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanMinimize": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanReadUserContentEdits": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanReport": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanReportToMaintainer": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanUnblockFromOrg": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanUndo": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerCanUpdate": (v92/*: any*/),
        "issue.timelineItems.edges.node.viewerDidAuthor": (v92/*: any*/),
        "issue.timelineItems.edges.node.willCloseSubject": (v92/*: any*/),
        "issue.timelineItems.edges.node.willCloseTarget": (v92/*: any*/),
        "issue.timelineItems.pageInfo": (v131/*: any*/),
        "issue.timelineItems.pageInfo.hasPreviousPage": (v92/*: any*/),
        "issue.timelineItems.pageInfo.startCursor": (v89/*: any*/),
        "issue.timelineItems.totalCount": (v96/*: any*/),
        "issue.title": (v86/*: any*/),
        "issue.titleHTML": (v86/*: any*/),
        "issue.updatedAt": (v93/*: any*/),
        "issue.url": (v87/*: any*/),
        "issue.viewerCanAssign": (v92/*: any*/),
        "issue.viewerCanComment": (v92/*: any*/),
        "issue.viewerCanConvertToDiscussion": (v119/*: any*/),
        "issue.viewerCanDelete": (v92/*: any*/),
        "issue.viewerCanLabel": (v92/*: any*/),
        "issue.viewerCanLock": (v119/*: any*/),
        "issue.viewerCanSetMilestone": (v92/*: any*/),
        "issue.viewerCanTransfer": (v92/*: any*/),
        "issue.viewerCanType": (v119/*: any*/),
        "issue.viewerCanUpdate": (v92/*: any*/),
        "issue.viewerCanUpdateMetadata": (v119/*: any*/),
        "issue.viewerCanUpdateNext": (v119/*: any*/),
        "issue.viewerDidAuthor": (v92/*: any*/),
        "viewer": (v85/*: any*/),
        "viewer.__typename": (v86/*: any*/),
        "viewer.avatarUrl": (v87/*: any*/),
        "viewer.enterpriseManagedEnterpriseId": (v89/*: any*/),
        "viewer.id": (v88/*: any*/),
        "viewer.isEmployee": (v92/*: any*/),
        "viewer.isEnterpriseManagedUser": (v119/*: any*/),
        "viewer.login": (v86/*: any*/),
        "viewer.name": (v89/*: any*/)
      }
    },
    "name": "IssueViewerTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "8ebafc32de47f8b3cf789e5936d5503d";

export default node;
