/**
 * @generated SignedSource<<5583800f1822f3b3c5412ce09c9e9555>>
 * @relayHash decd794acebd1dd1c7e8fb67e41fb980
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID decd794acebd1dd1c7e8fb67e41fb980

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
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
  "name": "title",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
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
  "name": "name",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
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
  "name": "isArchived",
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v15 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v16 = [
  (v15/*: any*/)
],
v17 = [
  (v3/*: any*/)
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
  "name": "description",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v21 = {
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
v22 = [
  (v2/*: any*/),
  (v8/*: any*/),
  (v3/*: any*/)
],
v23 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v22/*: any*/),
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
    (v7/*: any*/),
    (v23/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v26 = {
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
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v30 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v33 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
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
  "name": "includeIssueTypeEvents",
  "value": true
},
v37 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v38 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v36/*: any*/),
  (v37/*: any*/)
],
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
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
  "name": "pendingBlock",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v45 = [
  (v8/*: any*/)
],
v46 = {
  "kind": "InlineFragment",
  "selections": (v17/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v47 = {
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
            (v14/*: any*/),
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
                  "selections": (v45/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v45/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v45/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v45/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v46/*: any*/)
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
v48 = [
  (v2/*: any*/),
  (v46/*: any*/)
],
v49 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v17/*: any*/),
  "storageKey": null
},
v50 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v7/*: any*/),
    (v11/*: any*/),
    (v23/*: any*/)
  ],
  "storageKey": null
},
v52 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v50/*: any*/),
    (v9/*: any*/),
    (v5/*: any*/),
    (v21/*: any*/),
    (v51/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v53 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v55 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v53/*: any*/),
    (v9/*: any*/),
    (v5/*: any*/),
    (v20/*: any*/),
    (v25/*: any*/),
    (v54/*: any*/),
    (v51/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v56 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v30/*: any*/),
    (v26/*: any*/),
    (v8/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v58 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v57/*: any*/),
      (v7/*: any*/),
      (v18/*: any*/),
      (v19/*: any*/)
    ],
    "storageKey": null
  },
  (v12/*: any*/),
  (v41/*: any*/),
  (v56/*: any*/)
],
v59 = [
  (v3/*: any*/),
  (v8/*: any*/)
],
v60 = {
  "kind": "InlineFragment",
  "selections": (v59/*: any*/),
  "type": "User",
  "abstractKey": null
},
v61 = {
  "kind": "InlineFragment",
  "selections": (v59/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v62 = {
  "kind": "InlineFragment",
  "selections": (v59/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v63 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v9/*: any*/)
    ],
    "storageKey": null
  },
  (v12/*: any*/),
  (v41/*: any*/),
  (v56/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v64 = [
  (v41/*: any*/),
  (v12/*: any*/),
  (v56/*: any*/)
],
v65 = {
  "kind": "InlineFragment",
  "selections": [
    (v52/*: any*/),
    (v55/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v66 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v67 = [
  (v12/*: any*/),
  (v41/*: any*/),
  (v56/*: any*/)
],
v68 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    (v11/*: any*/),
    (v23/*: any*/)
  ],
  "storageKey": null
},
v69 = [
  (v49/*: any*/),
  (v12/*: any*/),
  (v3/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v50/*: any*/),
          (v9/*: any*/),
          (v5/*: any*/),
          (v21/*: any*/),
          (v68/*: any*/)
        ],
        "type": "Issue",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": [
          (v53/*: any*/),
          (v9/*: any*/),
          (v5/*: any*/),
          (v20/*: any*/),
          (v25/*: any*/),
          (v54/*: any*/),
          (v68/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      }
    ],
    "type": "ReferencedSubject",
    "abstractKey": "__isReferencedSubject"
  }
],
v70 = [
  (v12/*: any*/),
  (v56/*: any*/),
  (v41/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": (v69/*: any*/),
    "storageKey": null
  }
],
v71 = [
  (v12/*: any*/),
  (v56/*: any*/),
  (v41/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": (v69/*: any*/),
    "storageKey": null
  }
],
v72 = [
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
v73 = [
  (v12/*: any*/),
  (v56/*: any*/),
  (v41/*: any*/),
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
          (v4/*: any*/),
          (v9/*: any*/),
          (v5/*: any*/),
          (v20/*: any*/),
          (v25/*: any*/),
          (v54/*: any*/),
          (v24/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v46/*: any*/)
    ],
    "storageKey": null
  }
],
v74 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v50/*: any*/),
        (v9/*: any*/),
        (v21/*: any*/),
        (v51/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v53/*: any*/),
        (v9/*: any*/),
        (v20/*: any*/),
        (v25/*: any*/),
        (v54/*: any*/),
        (v51/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v75 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v76 = [
  (v65/*: any*/)
],
v77 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v4/*: any*/),
    (v9/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v78 = [
  (v7/*: any*/),
  (v18/*: any*/),
  (v3/*: any*/)
],
v79 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v78/*: any*/),
  "storageKey": null
},
v80 = [
  (v12/*: any*/),
  (v56/*: any*/),
  (v41/*: any*/),
  (v79/*: any*/)
],
v81 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v82 = {
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
          "kind": "TypeDiscriminator",
          "abstractKey": "__isIssueTimelineItems"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": (v22/*: any*/),
              "storageKey": null
            }
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v28/*: any*/),
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
                  "selections": (v22/*: any*/),
                  "storageKey": null
                },
                (v3/*: any*/),
                (v5/*: any*/),
                (v29/*: any*/),
                (v12/*: any*/)
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
                (v8/*: any*/),
                (v31/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            },
            (v3/*: any*/),
            (v32/*: any*/),
            {
              "alias": null,
              "args": [
                (v33/*: any*/)
              ],
              "kind": "ScalarField",
              "name": "bodyHTML",
              "storageKey": "bodyHTML(unfurlReferences:true)"
            },
            (v34/*: any*/),
            (v42/*: any*/),
            (v9/*: any*/),
            (v41/*: any*/),
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
                (v41/*: any*/),
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
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "repository",
              "plural": false,
              "selections": [
                (v3/*: any*/),
                (v7/*: any*/),
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
                    (v8/*: any*/),
                    (v9/*: any*/)
                  ],
                  "storageKey": null
                },
                (v11/*: any*/),
                (v13/*: any*/),
                (v6/*: any*/),
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
                        (v9/*: any*/),
                        (v8/*: any*/),
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
                (v43/*: any*/),
                (v44/*: any*/)
              ]
            },
            (v47/*: any*/)
          ],
          "type": "IssueComment",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "source",
              "plural": false,
              "selections": (v48/*: any*/),
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
                    (v49/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v46/*: any*/)
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
                (v52/*: any*/),
                (v55/*: any*/),
                (v46/*: any*/)
              ],
              "storageKey": null
            },
            (v56/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v58/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v58/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "assignee",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                (v60/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v8/*: any*/),
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
                (v61/*: any*/),
                (v62/*: any*/),
                (v46/*: any*/)
              ],
              "storageKey": null
            },
            (v12/*: any*/),
            (v41/*: any*/),
            (v56/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "assignee",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                (v60/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v59/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                (v61/*: any*/),
                (v62/*: any*/),
                (v46/*: any*/)
              ],
              "storageKey": null
            },
            (v12/*: any*/),
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                (v8/*: any*/),
                (v30/*: any*/),
                (v26/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v63/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v63/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v41/*: any*/),
            (v21/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                (v65/*: any*/),
                (v46/*: any*/)
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
                    (v9/*: any*/),
                    (v4/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v9/*: any*/),
                    (v5/*: any*/),
                    (v24/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v9/*: any*/),
                    (v66/*: any*/),
                    (v24/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v46/*: any*/)
              ],
              "storageKey": null
            },
            (v56/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v56/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v41/*: any*/),
            (v56/*: any*/),
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
            (v41/*: any*/),
            (v56/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "deletedCommentAuthor",
              "plural": false,
              "selections": (v22/*: any*/),
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
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v56/*: any*/),
            {
              "alias": "blockedUser",
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": [
                (v8/*: any*/),
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
          "type": "SubIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "SubIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "ParentIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "ParentIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
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
              "selections": (v48/*: any*/),
              "storageKey": null
            },
            (v56/*: any*/),
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
                (v9/*: any*/),
                (v66/*: any*/),
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
                        (v8/*: any*/),
                        (v31/*: any*/),
                        (v3/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v20/*: any*/),
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
                          "selections": (v72/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v72/*: any*/),
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
                    (v7/*: any*/),
                    (v23/*: any*/),
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
            },
            (v41/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v73/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v56/*: any*/),
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v6/*: any*/),
                (v9/*: any*/),
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
          "selections": (v73/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v56/*: any*/),
            (v41/*: any*/),
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
                    (v5/*: any*/),
                    (v74/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v5/*: any*/),
                    (v3/*: any*/),
                    (v74/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v46/*: any*/)
              ],
              "storageKey": null
            },
            (v75/*: any*/),
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
            (v56/*: any*/),
            (v41/*: any*/),
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
                  "selections": (v76/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v76/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v46/*: any*/)
              ],
              "storageKey": null
            },
            (v75/*: any*/),
            (v12/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v56/*: any*/),
            (v41/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                (v5/*: any*/),
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
            (v12/*: any*/),
            (v41/*: any*/),
            (v56/*: any*/),
            (v77/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v41/*: any*/),
            (v56/*: any*/),
            (v77/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v41/*: any*/),
            (v56/*: any*/),
            (v77/*: any*/),
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
            (v41/*: any*/),
            (v56/*: any*/),
            (v12/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v80/*: any*/),
          "type": "IssueTypeAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v80/*: any*/),
          "type": "IssueTypeRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v56/*: any*/),
            (v41/*: any*/),
            (v79/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "prevIssueType",
              "plural": false,
              "selections": (v78/*: any*/),
              "storageKey": null
            }
          ],
          "type": "IssueTypeChangedEvent",
          "abstractKey": null
        },
        {
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
        (v46/*: any*/)
      ],
      "storageKey": null
    },
    (v81/*: any*/)
  ],
  "storageKey": null
},
v83 = [
  "visibleEventsOnly",
  "includeIssueTypeEvents"
],
v84 = [
  (v36/*: any*/),
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v37/*: any*/)
],
v85 = [
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
v86 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v40/*: any*/),
    (v39/*: any*/)
  ],
  "storageKey": null
},
v87 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v88 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v89 = {
  "alias": null,
  "args": (v16/*: any*/),
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
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v3/*: any*/),
                (v4/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v42/*: any*/),
                (v9/*: any*/),
                {
                  "alias": null,
                  "args": (v87/*: any*/),
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
                        (v7/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v3/*: any*/),
                            (v88/*: any*/),
                            (v7/*: any*/),
                            (v57/*: any*/),
                            (v18/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v19/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v46/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v27/*: any*/),
                (v5/*: any*/),
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
              "args": (v87/*: any*/),
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
                    (v88/*: any*/),
                    (v7/*: any*/),
                    (v57/*: any*/),
                    (v18/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v46/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v2/*: any*/)
          ],
          "storageKey": null
        },
        (v81/*: any*/)
      ],
      "storageKey": null
    },
    (v86/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v90 = {
  "alias": null,
  "args": (v16/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v91 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v92 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v93 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v94 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v95 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v96 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v97 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v98 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v99 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v100 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
},
v101 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v102 = {
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
v103 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Sponsorship"
},
v104 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
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
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v108 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v109 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v110 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v111 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v112 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v113 = {
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
v114 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v115 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v116 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitSignature"
},
v117 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v118 = {
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
v119 = {
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
v120 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v121 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Discussion"
},
v122 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v123 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v124 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v125 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v126 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v127 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v128 = {
  "enumValues": (v127/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
},
v129 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v130 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v131 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v132 = {
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
v133 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
},
v134 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v135 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "ProjectV2"
},
v136 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "ReactionGroup"
},
v137 = {
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
v138 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReactorConnection"
},
v139 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Reactor"
},
v140 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v141 = {
  "enumValues": (v127/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "ProjectV2SingleSelectFieldOptionColor"
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
                "args": null,
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
              (v4/*: any*/),
              (v5/*: any*/),
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
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v8/*: any*/),
                      (v3/*: any*/),
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v10/*: any*/),
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
                    "args": null,
                    "kind": "ScalarField",
                    "name": "visibility",
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
                    "selections": [
                      (v14/*: any*/)
                    ],
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
                    "args": (v16/*: any*/),
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
                            "selections": (v17/*: any*/),
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
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "titleHTML",
                "storageKey": null
              },
              (v9/*: any*/),
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
                  (v7/*: any*/),
                  (v18/*: any*/),
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isEnabled",
                    "storageKey": null
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v20/*: any*/),
              (v21/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v5/*: any*/),
                  (v9/*: any*/),
                  (v24/*: any*/),
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v15/*: any*/),
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
                          (v6/*: any*/),
                          (v3/*: any*/),
                          (v7/*: any*/),
                          (v23/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v20/*: any*/),
                      (v25/*: any*/),
                      (v9/*: any*/),
                      (v5/*: any*/),
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
                    "name": "total",
                    "storageKey": null
                  },
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
                      (v8/*: any*/),
                      (v7/*: any*/),
                      (v26/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "assignees(first:20)"
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
                  (v4/*: any*/),
                  (v27/*: any*/),
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
                  (v9/*: any*/),
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
              (v12/*: any*/),
              (v28/*: any*/),
              (v29/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v30/*: any*/),
                  (v8/*: any*/),
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "profileUrl",
                    "storageKey": null
                  },
                  (v31/*: any*/)
                ],
                "storageKey": null
              },
              (v32/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v33/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v34/*: any*/),
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
                "kind": "ScalarField",
                "name": "viewerCanComment",
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
                "kind": "ScalarField",
                "name": "viewerCanLabel",
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
                "alias": "frontTimelineItems",
                "args": (v38/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "PageInfo",
                    "kind": "LinkedField",
                    "name": "pageInfo",
                    "plural": false,
                    "selections": [
                      (v39/*: any*/),
                      (v40/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v14/*: any*/),
                  (v82/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,includeIssueTypeEvents:true,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v38/*: any*/),
                "filters": (v83/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v84/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
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
                  (v14/*: any*/),
                  (v82/*: any*/)
                ],
                "storageKey": "timelineItems(includeIssueTypeEvents:true,last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v84/*: any*/),
                "filters": (v83/*: any*/),
                "handle": "connection",
                "key": "Issue__backTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v85/*: any*/),
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
                              (v18/*: any*/),
                              (v7/*: any*/),
                              (v57/*: any*/),
                              (v19/*: any*/),
                              (v9/*: any*/),
                              (v2/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v81/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v86/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v85/*: any*/),
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
                  (v41/*: any*/)
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v47/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v43/*: any*/),
                  (v44/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v89/*: any*/),
                      (v90/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v89/*: any*/),
                      (v90/*: any*/),
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
              (v8/*: any*/),
              (v26/*: any*/),
              (v7/*: any*/)
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
    "id": "decd794acebd1dd1c7e8fb67e41fb980",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": (v91/*: any*/),
        "issue.__isComment": (v92/*: any*/),
        "issue.__isIssueOrPullRequest": (v92/*: any*/),
        "issue.__isLabelable": (v92/*: any*/),
        "issue.__isNode": (v92/*: any*/),
        "issue.__isReactable": (v92/*: any*/),
        "issue.__typename": (v92/*: any*/),
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
        "issue.assignees.nodes.avatarUrl": (v93/*: any*/),
        "issue.assignees.nodes.id": (v94/*: any*/),
        "issue.assignees.nodes.login": (v92/*: any*/),
        "issue.assignees.nodes.name": (v95/*: any*/),
        "issue.author": (v96/*: any*/),
        "issue.author.__isActor": (v92/*: any*/),
        "issue.author.__typename": (v92/*: any*/),
        "issue.author.avatarUrl": (v93/*: any*/),
        "issue.author.id": (v94/*: any*/),
        "issue.author.login": (v92/*: any*/),
        "issue.author.profileUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "issue.backTimelineItems": (v97/*: any*/),
        "issue.backTimelineItems.edges": (v98/*: any*/),
        "issue.backTimelineItems.edges.cursor": (v92/*: any*/),
        "issue.backTimelineItems.edges.node": (v99/*: any*/),
        "issue.backTimelineItems.edges.node.__id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.__isComment": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.__isIssueTimelineItems": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.__isReactable": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.__isTimelineEvent": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.actor": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.actor.__isActor": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.actor.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.actor.avatarUrl": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.actor.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.actor.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.assignee": (v100/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.isCopilot": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.author": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.author.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.author.avatarUrl": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.author.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.author.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.authorAssociation": (v102/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v103/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v104/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.blockDuration": (v105/*: any*/),
        "issue.backTimelineItems.edges.node.blockedUser": (v106/*: any*/),
        "issue.backTimelineItems.edges.node.blockedUser.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.blockedUser.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.body": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.bodyHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.bodyVersion": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical": (v108/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.__isReferencedSubject": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.isDraft": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.isInMergeQueue": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.issueTitleHTML": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.pullTitleHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.isPrivate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.state": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.stateReason": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.closer": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.closer.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.abbreviatedOid": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.title": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.closer.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.closingProjectItemStatus": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.commit.abbreviatedOid": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.hasSignature": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.commit.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.message": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.messageBodyHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.commit.messageHeadlineHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.defaultBranch": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer": (v117/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.commonName": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.organization": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.keyFingerprint": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.keyId": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer": (v106/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.state": (v118/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject": (v117/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.commonName": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.emailAddress": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.organization": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.commit.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.commit.verificationStatus": (v119/*: any*/),
        "issue.backTimelineItems.edges.node.createdAt": (v104/*: any*/),
        "issue.backTimelineItems.edges.node.createdViaEmail": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.currentTitle": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.databaseId": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.discussion": (v121/*: any*/),
        "issue.backTimelineItems.edges.node.discussion.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.discussion.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.discussion.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf": (v108/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.isDraft": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.state": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.stateReason": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository": (v122/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository.nameWithOwner": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.__isReferencedSubject": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.isDraft": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.isInMergeQueue": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.issueTitleHTML": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.pullTitleHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.isPrivate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.state": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.stateReason": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v124/*: any*/),
        "issue.backTimelineItems.edges.node.isHidden": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.issue": (v125/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.issue.databaseId": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.issue.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.issue.locked": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.issue.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.issueType": (v126/*: any*/),
        "issue.backTimelineItems.edges.node.issueType.color": (v128/*: any*/),
        "issue.backTimelineItems.edges.node.issueType.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.issueType.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.label": (v129/*: any*/),
        "issue.backTimelineItems.edges.node.label.color": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.label.description": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.label.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.label.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.label.nameHTML": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.lastEditedAt": (v130/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit": (v131/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.lockReason": (v132/*: any*/),
        "issue.backTimelineItems.edges.node.milestone": (v133/*: any*/),
        "issue.backTimelineItems.edges.node.milestone.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.milestone.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.milestoneTitle": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.minimizedReason": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.parent": (v134/*: any*/),
        "issue.backTimelineItems.edges.node.parent.__isReferencedSubject": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.parent.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.parent.databaseId": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.parent.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.isDraft": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.parent.isInMergeQueue": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.parent.issueTitleHTML": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.parent.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.parent.pullTitleHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.isPrivate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.parent.state": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.parent.stateReason": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.parent.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.pendingBlock": (v124/*: any*/),
        "issue.backTimelineItems.edges.node.pendingMinimizeReason": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.pendingUnblock": (v124/*: any*/),
        "issue.backTimelineItems.edges.node.pendingUndo": (v124/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType": (v126/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType.color": (v128/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.previousStatus": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.previousTitle": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.project": (v135/*: any*/),
        "issue.backTimelineItems.edges.node.project.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.project.title": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.project.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups": (v136/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.content": (v137/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors": (v138/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes": (v139/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.referencedAt": (v104/*: any*/),
        "issue.backTimelineItems.edges.node.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.repository.databaseId": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.repository.isPrivate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.repository.nameWithOwner": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.repository.slashCommandsEnabled": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.showSpammyBadge": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.source": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.source.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.source.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.source.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.stateReason": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.status": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue": (v134/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.__isReferencedSubject": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.databaseId": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.isDraft": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.isInMergeQueue": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.issueTitleHTML": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.pullTitleHTML": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.isPrivate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.state": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.stateReason": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.subject": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.subject.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subject.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subject.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.isDraft": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.subject.isInMergeQueue": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.subject.number": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.name": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner.login": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subject.state": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.subject.title": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.subject.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.target": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.target.__isNode": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.target.__typename": (v92/*: any*/),
        "issue.backTimelineItems.edges.node.target.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.target.repository": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.target.repository.id": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.url": (v93/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanBlockFromOrg": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanDelete": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanMinimize": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanReadUserContentEdits": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanReport": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanReportToMaintainer": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanUnblockFromOrg": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanUndo": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanUpdate": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.viewerDidAuthor": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.willCloseSubject": (v101/*: any*/),
        "issue.backTimelineItems.edges.node.willCloseTarget": (v101/*: any*/),
        "issue.backTimelineItems.pageInfo": (v140/*: any*/),
        "issue.backTimelineItems.pageInfo.hasPreviousPage": (v101/*: any*/),
        "issue.backTimelineItems.pageInfo.startCursor": (v95/*: any*/),
        "issue.backTimelineItems.totalCount": (v109/*: any*/),
        "issue.body": (v92/*: any*/),
        "issue.bodyHTML": (v107/*: any*/),
        "issue.bodyVersion": (v92/*: any*/),
        "issue.createdAt": (v104/*: any*/),
        "issue.databaseId": (v120/*: any*/),
        "issue.duplicateOf": (v134/*: any*/),
        "issue.duplicateOf.id": (v94/*: any*/),
        "issue.duplicateOf.number": (v109/*: any*/),
        "issue.duplicateOf.repository": (v110/*: any*/),
        "issue.duplicateOf.repository.id": (v94/*: any*/),
        "issue.duplicateOf.repository.name": (v92/*: any*/),
        "issue.duplicateOf.repository.owner": (v111/*: any*/),
        "issue.duplicateOf.repository.owner.__typename": (v92/*: any*/),
        "issue.duplicateOf.repository.owner.id": (v94/*: any*/),
        "issue.duplicateOf.repository.owner.login": (v92/*: any*/),
        "issue.duplicateOf.url": (v93/*: any*/),
        "issue.frontTimelineItems": (v97/*: any*/),
        "issue.frontTimelineItems.edges": (v98/*: any*/),
        "issue.frontTimelineItems.edges.cursor": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node": (v99/*: any*/),
        "issue.frontTimelineItems.edges.node.__id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.__isComment": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.__isIssueTimelineItems": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.__isReactable": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.__isTimelineEvent": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.actor": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.__isActor": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.avatarUrl": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee": (v100/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.isCopilot": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.author": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.author.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.author.avatarUrl": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.author.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.author.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.authorAssociation": (v102/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v103/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v104/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.blockDuration": (v105/*: any*/),
        "issue.frontTimelineItems.edges.node.blockedUser": (v106/*: any*/),
        "issue.frontTimelineItems.edges.node.blockedUser.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.blockedUser.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.body": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.bodyHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.bodyVersion": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical": (v108/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.__isReferencedSubject": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.isDraft": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.isInMergeQueue": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.issueTitleHTML": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.pullTitleHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.isPrivate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.state": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.stateReason": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.closer": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.abbreviatedOid": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.title": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.closingProjectItemStatus": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.abbreviatedOid": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.hasSignature": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.message": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.messageBodyHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.messageHeadlineHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.defaultBranch": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer": (v117/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.commonName": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.organization": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.keyFingerprint": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.keyId": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer": (v106/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.state": (v118/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject": (v117/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.commonName": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.emailAddress": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.organization": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.verificationStatus": (v119/*: any*/),
        "issue.frontTimelineItems.edges.node.createdAt": (v104/*: any*/),
        "issue.frontTimelineItems.edges.node.createdViaEmail": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.currentTitle": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.databaseId": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion": (v121/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf": (v108/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.isDraft": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.state": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.stateReason": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository": (v122/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository.nameWithOwner": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.__isReferencedSubject": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.isDraft": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.isInMergeQueue": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.issueTitleHTML": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.pullTitleHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.isPrivate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.state": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.stateReason": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v124/*: any*/),
        "issue.frontTimelineItems.edges.node.isHidden": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.issue": (v125/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.databaseId": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.locked": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType": (v126/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType.color": (v128/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.label": (v129/*: any*/),
        "issue.frontTimelineItems.edges.node.label.color": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.label.description": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.label.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.label.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.label.nameHTML": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.lastEditedAt": (v130/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit": (v131/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.lockReason": (v132/*: any*/),
        "issue.frontTimelineItems.edges.node.milestone": (v133/*: any*/),
        "issue.frontTimelineItems.edges.node.milestone.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.milestone.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.milestoneTitle": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.minimizedReason": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.parent": (v134/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.__isReferencedSubject": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.databaseId": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.isDraft": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.isInMergeQueue": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.issueTitleHTML": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.pullTitleHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.isPrivate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.state": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.stateReason": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingBlock": (v124/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingMinimizeReason": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingUnblock": (v124/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingUndo": (v124/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType": (v126/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType.color": (v128/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.previousStatus": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.previousTitle": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.project": (v135/*: any*/),
        "issue.frontTimelineItems.edges.node.project.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.project.title": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.project.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups": (v136/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.content": (v137/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors": (v138/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes": (v139/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.referencedAt": (v104/*: any*/),
        "issue.frontTimelineItems.edges.node.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.databaseId": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.isPrivate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.nameWithOwner": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.slashCommandsEnabled": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.showSpammyBadge": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.source": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.source.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.source.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.source.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.stateReason": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.status": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue": (v134/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.__isReferencedSubject": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.databaseId": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.isDraft": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.isInMergeQueue": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.issueTitleHTML": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.pullTitleHTML": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.isPrivate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.state": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.stateReason": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.subject": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.isDraft": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.isInMergeQueue": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.number": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.name": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner.login": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.state": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.title": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.target": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.target.__isNode": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.target.__typename": (v92/*: any*/),
        "issue.frontTimelineItems.edges.node.target.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.target.repository": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.target.repository.id": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.url": (v93/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanBlockFromOrg": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanDelete": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanMinimize": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanReadUserContentEdits": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanReport": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanReportToMaintainer": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanUnblockFromOrg": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanUndo": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanUpdate": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerDidAuthor": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.willCloseSubject": (v101/*: any*/),
        "issue.frontTimelineItems.edges.node.willCloseTarget": (v101/*: any*/),
        "issue.frontTimelineItems.pageInfo": (v140/*: any*/),
        "issue.frontTimelineItems.pageInfo.endCursor": (v95/*: any*/),
        "issue.frontTimelineItems.pageInfo.hasNextPage": (v101/*: any*/),
        "issue.frontTimelineItems.totalCount": (v109/*: any*/),
        "issue.id": (v94/*: any*/),
        "issue.isPinned": (v124/*: any*/),
        "issue.issueType": (v126/*: any*/),
        "issue.issueType.color": (v128/*: any*/),
        "issue.issueType.description": (v95/*: any*/),
        "issue.issueType.id": (v94/*: any*/),
        "issue.issueType.isEnabled": (v101/*: any*/),
        "issue.issueType.name": (v92/*: any*/),
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
        "issue.labels.edges.cursor": (v92/*: any*/),
        "issue.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "issue.labels.edges.node.__typename": (v92/*: any*/),
        "issue.labels.edges.node.color": (v92/*: any*/),
        "issue.labels.edges.node.description": (v95/*: any*/),
        "issue.labels.edges.node.id": (v94/*: any*/),
        "issue.labels.edges.node.name": (v92/*: any*/),
        "issue.labels.edges.node.nameHTML": (v92/*: any*/),
        "issue.labels.edges.node.url": (v93/*: any*/),
        "issue.labels.pageInfo": (v140/*: any*/),
        "issue.labels.pageInfo.endCursor": (v95/*: any*/),
        "issue.labels.pageInfo.hasNextPage": (v101/*: any*/),
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
        "issue.linkedPullRequests.nodes.id": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.isDraft": (v101/*: any*/),
        "issue.linkedPullRequests.nodes.number": (v109/*: any*/),
        "issue.linkedPullRequests.nodes.repository": (v110/*: any*/),
        "issue.linkedPullRequests.nodes.repository.id": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.repository.name": (v92/*: any*/),
        "issue.linkedPullRequests.nodes.repository.nameWithOwner": (v92/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner": (v111/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.__typename": (v92/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.id": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.login": (v92/*: any*/),
        "issue.linkedPullRequests.nodes.state": (v112/*: any*/),
        "issue.linkedPullRequests.nodes.url": (v93/*: any*/),
        "issue.locked": (v101/*: any*/),
        "issue.milestone": (v133/*: any*/),
        "issue.milestone.closed": (v101/*: any*/),
        "issue.milestone.closedAt": (v130/*: any*/),
        "issue.milestone.dueOn": (v130/*: any*/),
        "issue.milestone.id": (v94/*: any*/),
        "issue.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "issue.milestone.title": (v92/*: any*/),
        "issue.milestone.url": (v93/*: any*/),
        "issue.number": (v109/*: any*/),
        "issue.pendingBlock": (v124/*: any*/),
        "issue.pendingUnblock": (v124/*: any*/),
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
        "issue.projectItemsNext.edges.cursor": (v92/*: any*/),
        "issue.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "issue.projectItemsNext.edges.node.__typename": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "issue.projectItemsNext.edges.node.fieldValueByName.__isNode": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.__typename": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.color": (v141/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.id": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.name": (v95/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v95/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.optionId": (v95/*: any*/),
        "issue.projectItemsNext.edges.node.id": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.isArchived": (v101/*: any*/),
        "issue.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "issue.projectItemsNext.edges.node.project.__typename": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.closed": (v101/*: any*/),
        "issue.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "issue.projectItemsNext.edges.node.project.field.__isNode": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.__typename": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.id": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.name": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "issue.projectItemsNext.edges.node.project.field.options.color": (v141/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.description": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.id": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.name": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.nameHTML": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.optionId": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v101/*: any*/),
        "issue.projectItemsNext.edges.node.project.id": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.number": (v109/*: any*/),
        "issue.projectItemsNext.edges.node.project.template": (v101/*: any*/),
        "issue.projectItemsNext.edges.node.project.title": (v92/*: any*/),
        "issue.projectItemsNext.edges.node.project.url": (v93/*: any*/),
        "issue.projectItemsNext.edges.node.project.viewerCanUpdate": (v101/*: any*/),
        "issue.projectItemsNext.pageInfo": (v140/*: any*/),
        "issue.projectItemsNext.pageInfo.endCursor": (v95/*: any*/),
        "issue.projectItemsNext.pageInfo.hasNextPage": (v101/*: any*/),
        "issue.reactionGroups": (v136/*: any*/),
        "issue.reactionGroups.content": (v137/*: any*/),
        "issue.reactionGroups.reactors": (v138/*: any*/),
        "issue.reactionGroups.reactors.nodes": (v139/*: any*/),
        "issue.reactionGroups.reactors.nodes.__isNode": (v92/*: any*/),
        "issue.reactionGroups.reactors.nodes.__typename": (v92/*: any*/),
        "issue.reactionGroups.reactors.nodes.id": (v94/*: any*/),
        "issue.reactionGroups.reactors.nodes.login": (v92/*: any*/),
        "issue.reactionGroups.reactors.totalCount": (v109/*: any*/),
        "issue.reactionGroups.viewerHasReacted": (v101/*: any*/),
        "issue.repository": (v110/*: any*/),
        "issue.repository.databaseId": (v120/*: any*/),
        "issue.repository.id": (v94/*: any*/),
        "issue.repository.isArchived": (v101/*: any*/),
        "issue.repository.isPrivate": (v101/*: any*/),
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
        "issue.repository.issueTypes.edges.node": (v126/*: any*/),
        "issue.repository.issueTypes.edges.node.id": (v94/*: any*/),
        "issue.repository.name": (v92/*: any*/),
        "issue.repository.nameWithOwner": (v92/*: any*/),
        "issue.repository.owner": (v111/*: any*/),
        "issue.repository.owner.__typename": (v92/*: any*/),
        "issue.repository.owner.id": (v94/*: any*/),
        "issue.repository.owner.login": (v92/*: any*/),
        "issue.repository.owner.url": (v93/*: any*/),
        "issue.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "issue.repository.pinnedIssues.totalCount": (v109/*: any*/),
        "issue.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "issue.repository.planFeatures.maximumAssignees": (v109/*: any*/),
        "issue.repository.slashCommandsEnabled": (v101/*: any*/),
        "issue.repository.viewerCanInteract": (v101/*: any*/),
        "issue.repository.viewerCanPinIssues": (v101/*: any*/),
        "issue.repository.viewerInteractionLimitReasonHTML": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "HTML"
        },
        "issue.repository.visibility": {
          "enumValues": [
            "INTERNAL",
            "PRIVATE",
            "PUBLIC"
          ],
          "nullable": false,
          "plural": false,
          "type": "RepositoryVisibility"
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
        "issue.stateReason": (v113/*: any*/),
        "issue.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "issue.subIssuesSummary.completed": (v109/*: any*/),
        "issue.subIssuesSummary.total": (v109/*: any*/),
        "issue.title": (v92/*: any*/),
        "issue.titleHTML": (v92/*: any*/),
        "issue.updatedAt": (v104/*: any*/),
        "issue.url": (v93/*: any*/),
        "issue.viewerCanAssign": (v101/*: any*/),
        "issue.viewerCanComment": (v101/*: any*/),
        "issue.viewerCanConvertToDiscussion": (v124/*: any*/),
        "issue.viewerCanDelete": (v101/*: any*/),
        "issue.viewerCanLabel": (v101/*: any*/),
        "issue.viewerCanLock": (v124/*: any*/),
        "issue.viewerCanSetMilestone": (v101/*: any*/),
        "issue.viewerCanTransfer": (v101/*: any*/),
        "issue.viewerCanType": (v124/*: any*/),
        "issue.viewerCanUpdate": (v101/*: any*/),
        "issue.viewerCanUpdateMetadata": (v124/*: any*/),
        "issue.viewerCanUpdateNext": (v124/*: any*/),
        "issue.viewerDidAuthor": (v101/*: any*/),
        "viewer": (v91/*: any*/),
        "viewer.__typename": (v92/*: any*/),
        "viewer.avatarUrl": (v93/*: any*/),
        "viewer.enterpriseManagedEnterpriseId": (v95/*: any*/),
        "viewer.id": (v94/*: any*/),
        "viewer.isEnterpriseManagedUser": (v124/*: any*/),
        "viewer.login": (v92/*: any*/),
        "viewer.name": (v95/*: any*/)
      }
    },
    "name": "IssueViewerTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "f0fccd77e24368a75d68ed8e214a6a8d";

export default node;
