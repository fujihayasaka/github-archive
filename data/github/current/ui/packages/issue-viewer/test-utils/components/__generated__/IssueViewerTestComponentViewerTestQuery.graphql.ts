/**
 * @generated SignedSource<<b73e5e1b34db184124c08ec7a938dcf8>>
 * @relayHash 98b0037a9e8ca621757bdcfd1911fea1
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 98b0037a9e8ca621757bdcfd1911fea1

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerTestComponentViewerTestQuery$variables = Record<PropertyKey, never>;
export type IssueViewerTestComponentViewerTestQuery$data = {
  readonly repository: {
    readonly isOwnerEnterpriseManaged: boolean | null | undefined;
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueViewerIssue">;
    } | null | undefined;
  } | null | undefined;
  readonly safeViewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
  } | null | undefined;
};
export type IssueViewerTestComponentViewerTestQuery = {
  response: IssueViewerTestComponentViewerTestQuery$data;
  variables: IssueViewerTestComponentViewerTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOwnerEnterpriseManaged",
  "storageKey": null
},
v2 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 33
  }
],
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
  "name": "__typename",
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
  "name": "isArchived",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v16 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v17 = [
  (v16/*: any*/)
],
v18 = [
  (v3/*: any*/)
],
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
  (v8/*: any*/),
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
    (v7/*: any*/),
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
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v31 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v34 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v37 = {
  "kind": "Literal",
  "name": "includeIssueTypeEvents",
  "value": true
},
v38 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v39 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v37/*: any*/),
  (v38/*: any*/)
],
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingBlock",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v46 = [
  (v9/*: any*/)
],
v47 = {
  "kind": "InlineFragment",
  "selections": (v18/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
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
            (v15/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v8/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v46/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v46/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v46/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v46/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v47/*: any*/)
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
v49 = [
  (v8/*: any*/),
  (v47/*: any*/)
],
v50 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v18/*: any*/),
  "storageKey": null
},
v51 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v52 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v7/*: any*/),
    (v12/*: any*/),
    (v24/*: any*/)
  ],
  "storageKey": null
},
v53 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v51/*: any*/),
    (v10/*: any*/),
    (v5/*: any*/),
    (v22/*: any*/),
    (v52/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v54 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v55 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v56 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v54/*: any*/),
    (v10/*: any*/),
    (v5/*: any*/),
    (v21/*: any*/),
    (v26/*: any*/),
    (v55/*: any*/),
    (v52/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v31/*: any*/),
    (v27/*: any*/),
    (v9/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v58 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v59 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v58/*: any*/),
      (v7/*: any*/),
      (v19/*: any*/),
      (v20/*: any*/)
    ],
    "storageKey": null
  },
  (v13/*: any*/),
  (v42/*: any*/),
  (v57/*: any*/)
],
v60 = [
  (v3/*: any*/),
  (v9/*: any*/)
],
v61 = {
  "kind": "InlineFragment",
  "selections": (v60/*: any*/),
  "type": "User",
  "abstractKey": null
},
v62 = {
  "kind": "InlineFragment",
  "selections": (v60/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v63 = {
  "kind": "InlineFragment",
  "selections": (v60/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v64 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v10/*: any*/)
    ],
    "storageKey": null
  },
  (v13/*: any*/),
  (v42/*: any*/),
  (v57/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v65 = [
  (v42/*: any*/),
  (v13/*: any*/),
  (v57/*: any*/)
],
v66 = {
  "kind": "InlineFragment",
  "selections": [
    (v53/*: any*/),
    (v56/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v67 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v68 = [
  (v13/*: any*/),
  (v42/*: any*/),
  (v57/*: any*/)
],
v69 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    (v12/*: any*/),
    (v24/*: any*/)
  ],
  "storageKey": null
},
v70 = [
  (v50/*: any*/),
  (v13/*: any*/),
  (v3/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      (v8/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v51/*: any*/),
          (v10/*: any*/),
          (v5/*: any*/),
          (v22/*: any*/),
          (v69/*: any*/)
        ],
        "type": "Issue",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": [
          (v54/*: any*/),
          (v10/*: any*/),
          (v5/*: any*/),
          (v21/*: any*/),
          (v26/*: any*/),
          (v55/*: any*/),
          (v69/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      }
    ],
    "type": "ReferencedSubject",
    "abstractKey": "__isReferencedSubject"
  }
],
v71 = [
  (v13/*: any*/),
  (v57/*: any*/),
  (v42/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": (v70/*: any*/),
    "storageKey": null
  }
],
v72 = [
  (v13/*: any*/),
  (v57/*: any*/),
  (v42/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": (v70/*: any*/),
    "storageKey": null
  }
],
v73 = [
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
v74 = [
  (v13/*: any*/),
  (v57/*: any*/),
  (v42/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v8/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v4/*: any*/),
          (v10/*: any*/),
          (v5/*: any*/),
          (v21/*: any*/),
          (v26/*: any*/),
          (v55/*: any*/),
          (v25/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v47/*: any*/)
    ],
    "storageKey": null
  }
],
v75 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v51/*: any*/),
        (v10/*: any*/),
        (v22/*: any*/),
        (v52/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v54/*: any*/),
        (v10/*: any*/),
        (v21/*: any*/),
        (v26/*: any*/),
        (v55/*: any*/),
        (v52/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v76 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v77 = [
  (v66/*: any*/)
],
v78 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v4/*: any*/),
    (v10/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v79 = [
  (v7/*: any*/),
  (v19/*: any*/),
  (v3/*: any*/)
],
v80 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v79/*: any*/),
  "storageKey": null
},
v81 = [
  (v13/*: any*/),
  (v57/*: any*/),
  (v42/*: any*/),
  (v80/*: any*/)
],
v82 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v83 = {
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
        (v8/*: any*/),
        {
          "kind": "TypeDiscriminator",
          "abstractKey": "__isIssueTimelineItems"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": (v23/*: any*/),
              "storageKey": null
            }
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v29/*: any*/),
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
                (v5/*: any*/),
                (v30/*: any*/),
                (v13/*: any*/)
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
                (v8/*: any*/),
                (v9/*: any*/),
                (v32/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            },
            (v3/*: any*/),
            (v33/*: any*/),
            {
              "alias": null,
              "args": [
                (v34/*: any*/)
              ],
              "kind": "ScalarField",
              "name": "bodyHTML",
              "storageKey": "bodyHTML(unfurlReferences:true)"
            },
            (v35/*: any*/),
            (v43/*: any*/),
            (v10/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "authorAssociation",
              "storageKey": null
            },
            (v36/*: any*/),
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
                (v42/*: any*/),
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
                    (v8/*: any*/),
                    (v3/*: any*/),
                    (v9/*: any*/),
                    (v10/*: any*/)
                  ],
                  "storageKey": null
                },
                (v12/*: any*/),
                (v14/*: any*/),
                (v6/*: any*/),
                (v13/*: any*/)
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
                        (v8/*: any*/),
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
                (v44/*: any*/),
                (v45/*: any*/)
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
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "source",
              "plural": false,
              "selections": (v49/*: any*/),
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
            (v13/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "target",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v50/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v47/*: any*/)
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
                (v8/*: any*/),
                {
                  "kind": "TypeDiscriminator",
                  "abstractKey": "__isReferencedSubject"
                },
                (v53/*: any*/),
                (v56/*: any*/),
                (v47/*: any*/)
              ],
              "storageKey": null
            },
            (v57/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v59/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v59/*: any*/),
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
                (v8/*: any*/),
                (v61/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v9/*: any*/),
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
                (v62/*: any*/),
                (v63/*: any*/),
                (v47/*: any*/)
              ],
              "storageKey": null
            },
            (v13/*: any*/),
            (v42/*: any*/),
            (v57/*: any*/)
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
                (v8/*: any*/),
                (v61/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v60/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                (v62/*: any*/),
                (v63/*: any*/),
                (v47/*: any*/)
              ],
              "storageKey": null
            },
            (v13/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                (v9/*: any*/),
                (v31/*: any*/),
                (v27/*: any*/),
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
          "selections": (v64/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v65/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v65/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v65/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v42/*: any*/),
            (v22/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                (v66/*: any*/),
                (v47/*: any*/)
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
                (v8/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v4/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v5/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v67/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v47/*: any*/)
              ],
              "storageKey": null
            },
            (v57/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v57/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v42/*: any*/),
            (v57/*: any*/),
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
            (v13/*: any*/),
            (v42/*: any*/),
            (v57/*: any*/),
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
            (v13/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v57/*: any*/),
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
          "selections": (v71/*: any*/),
          "type": "SubIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "SubIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v72/*: any*/),
          "type": "ParentIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v72/*: any*/),
          "type": "ParentIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
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
              "selections": (v49/*: any*/),
              "storageKey": null
            },
            (v57/*: any*/),
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
                (v67/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "signature",
                  "plural": false,
                  "selections": [
                    (v8/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "User",
                      "kind": "LinkedField",
                      "name": "signer",
                      "plural": false,
                      "selections": [
                        (v9/*: any*/),
                        (v32/*: any*/),
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
                          "selections": (v73/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v73/*: any*/),
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
            },
            (v42/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v74/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v57/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v6/*: any*/),
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
          "selections": (v74/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v57/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v5/*: any*/),
                    (v75/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v5/*: any*/),
                    (v3/*: any*/),
                    (v75/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v47/*: any*/)
              ],
              "storageKey": null
            },
            (v76/*: any*/),
            (v13/*: any*/),
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
            (v57/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v77/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v77/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v47/*: any*/)
              ],
              "storageKey": null
            },
            (v76/*: any*/),
            (v13/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v57/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v10/*: any*/),
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
            (v13/*: any*/),
            (v42/*: any*/),
            (v57/*: any*/),
            (v78/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v57/*: any*/),
            (v78/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v57/*: any*/),
            (v78/*: any*/),
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
            (v42/*: any*/),
            (v57/*: any*/),
            (v13/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v81/*: any*/),
          "type": "IssueTypeAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v81/*: any*/),
          "type": "IssueTypeRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v57/*: any*/),
            (v42/*: any*/),
            (v80/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "prevIssueType",
              "plural": false,
              "selections": (v79/*: any*/),
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
        (v47/*: any*/)
      ],
      "storageKey": null
    },
    (v82/*: any*/)
  ],
  "storageKey": null
},
v84 = [
  "visibleEventsOnly",
  "includeIssueTypeEvents"
],
v85 = [
  (v37/*: any*/),
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v38/*: any*/)
],
v86 = [
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
v87 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v41/*: any*/),
    (v40/*: any*/)
  ],
  "storageKey": null
},
v88 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v89 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v90 = {
  "alias": null,
  "args": (v17/*: any*/),
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
            (v11/*: any*/),
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
                (v43/*: any*/),
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": (v88/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v8/*: any*/),
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
                            (v89/*: any*/),
                            (v7/*: any*/),
                            (v58/*: any*/),
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
                    (v47/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v28/*: any*/),
                (v5/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v8/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v88/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v89/*: any*/),
                    (v7/*: any*/),
                    (v58/*: any*/),
                    (v19/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v47/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v8/*: any*/)
          ],
          "storageKey": null
        },
        (v82/*: any*/)
      ],
      "storageKey": null
    },
    (v87/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v91 = {
  "alias": null,
  "args": (v17/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v92 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v93 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v94 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
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
  "type": "String"
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
  "type": "String"
},
v99 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v100 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v101 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v102 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v103 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
},
v104 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
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
  "type": "DateTime"
},
v108 = {
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
v109 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v110 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v111 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v112 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v113 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v114 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v115 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v116 = {
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
v117 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v118 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v119 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitSignature"
},
v120 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v121 = {
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
v122 = {
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
v123 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v124 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Discussion"
},
v125 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v126 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v127 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v128 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v129 = {
  "enumValues": (v128/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
},
v130 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v131 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v132 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v133 = {
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
v134 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
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
  "enumValues": (v128/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "ProjectV2SingleSelectFieldOptionColor"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueViewerTestComponentViewerTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          {
            "alias": null,
            "args": (v2/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueViewerIssue"
              }
            ],
            "storageKey": "issue(number:33)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "safeViewer",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "IssueViewerViewer"
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
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueViewerTestComponentViewerTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          {
            "alias": null,
            "args": (v2/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v3/*: any*/),
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
                      (v8/*: any*/),
                      (v9/*: any*/),
                      (v3/*: any*/),
                      (v10/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v11/*: any*/),
                  (v12/*: any*/),
                  (v13/*: any*/),
                  (v14/*: any*/),
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
                      (v15/*: any*/)
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
                    "args": (v17/*: any*/),
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
                            "selections": (v18/*: any*/),
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
                  (v7/*: any*/),
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
                  (v5/*: any*/),
                  (v10/*: any*/),
                  (v25/*: any*/),
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v16/*: any*/),
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
                          (v24/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v21/*: any*/),
                      (v26/*: any*/),
                      (v10/*: any*/),
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
                      (v9/*: any*/),
                      (v7/*: any*/),
                      (v27/*: any*/)
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
                  (v28/*: any*/),
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
              (v13/*: any*/),
              (v29/*: any*/),
              (v30/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v8/*: any*/),
                  (v31/*: any*/),
                  (v9/*: any*/),
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "profileUrl",
                    "storageKey": null
                  },
                  (v32/*: any*/)
                ],
                "storageKey": null
              },
              (v33/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v34/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v35/*: any*/),
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
              (v36/*: any*/),
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
                "args": (v39/*: any*/),
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
                      (v40/*: any*/),
                      (v41/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v15/*: any*/),
                  (v83/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,includeIssueTypeEvents:true,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v39/*: any*/),
                "filters": (v84/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v85/*: any*/),
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
                  (v15/*: any*/),
                  (v83/*: any*/)
                ],
                "storageKey": "timelineItems(includeIssueTypeEvents:true,last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v85/*: any*/),
                "filters": (v84/*: any*/),
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
                    "args": (v86/*: any*/),
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
                              (v7/*: any*/),
                              (v58/*: any*/),
                              (v20/*: any*/),
                              (v10/*: any*/),
                              (v8/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v82/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v87/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v86/*: any*/),
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
                  (v42/*: any*/)
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v48/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v44/*: any*/),
                  (v45/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v90/*: any*/),
                      (v91/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v90/*: any*/),
                      (v91/*: any*/),
                      (v43/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              }
            ],
            "storageKey": "issue(number:33)"
          },
          (v3/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "safeViewer",
        "plural": false,
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
          (v3/*: any*/),
          (v27/*: any*/),
          (v7/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "98b0037a9e8ca621757bdcfd1911fea1",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": (v92/*: any*/),
        "repository.id": (v93/*: any*/),
        "repository.isOwnerEnterpriseManaged": (v94/*: any*/),
        "repository.issue": (v95/*: any*/),
        "repository.issue.__isComment": (v96/*: any*/),
        "repository.issue.__isIssueOrPullRequest": (v96/*: any*/),
        "repository.issue.__isLabelable": (v96/*: any*/),
        "repository.issue.__isNode": (v96/*: any*/),
        "repository.issue.__isReactable": (v96/*: any*/),
        "repository.issue.assignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "UserConnection"
        },
        "repository.issue.assignees.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "repository.issue.assignees.nodes.avatarUrl": (v97/*: any*/),
        "repository.issue.assignees.nodes.id": (v93/*: any*/),
        "repository.issue.assignees.nodes.login": (v96/*: any*/),
        "repository.issue.assignees.nodes.name": (v98/*: any*/),
        "repository.issue.author": (v99/*: any*/),
        "repository.issue.author.__isActor": (v96/*: any*/),
        "repository.issue.author.__typename": (v96/*: any*/),
        "repository.issue.author.avatarUrl": (v97/*: any*/),
        "repository.issue.author.id": (v93/*: any*/),
        "repository.issue.author.login": (v96/*: any*/),
        "repository.issue.author.profileUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "repository.issue.backTimelineItems": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.cursor": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node": (v102/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isComment": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isIssueTimelineItems": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isReactable": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isTimelineEvent": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__isActor": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.avatarUrl": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.isCopilot": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.avatarUrl": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorAssociation": (v105/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v106/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v107/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockDuration": (v108/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser": (v109/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.body": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyVersion": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical": (v111/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isDraft": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isInMergeQueue": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.issueTitleHTML": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.pullTitleHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.isPrivate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.state": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.stateReason": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.abbreviatedOid": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.title": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closingProjectItemStatus": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.abbreviatedOid": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.hasSignature": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.message": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageBodyHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageHeadlineHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.defaultBranch": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer": (v120/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.commonName": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organization": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyFingerprint": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyId": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer": (v109/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.state": (v121/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject": (v120/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.commonName": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.emailAddress": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organization": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.verificationStatus": (v122/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdAt": (v107/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdViaEmail": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.currentTitle": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.databaseId": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion": (v124/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf": (v111/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isDraft": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.state": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.stateReason": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository": (v92/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.nameWithOwner": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource": (v125/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isDraft": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isInMergeQueue": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.issueTitleHTML": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.pullTitleHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.isPrivate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.state": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.stateReason": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isHidden": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue": (v126/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.databaseId": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.locked": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType": (v127/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.color": (v129/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label": (v130/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.color": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.description": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.nameHTML": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastEditedAt": (v131/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit": (v132/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lockReason": (v133/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone": (v134/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestoneTitle": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.minimizedReason": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.databaseId": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.isDraft": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.isInMergeQueue": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.issueTitleHTML": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.pullTitleHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.isPrivate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.state": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.stateReason": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingBlock": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingMinimizeReason": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUnblock": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUndo": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType": (v127/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.color": (v129/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousStatus": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousTitle": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project": (v135/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.title": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups": (v136/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.content": (v137/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors": (v138/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes": (v139/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.referencedAt": (v107/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.databaseId": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.isPrivate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.nameWithOwner": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.slashCommandsEnabled": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.showSpammyBadge": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source": (v125/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.stateReason": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.status": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.databaseId": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.isDraft": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.isInMergeQueue": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.issueTitleHTML": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.pullTitleHTML": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.isPrivate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.state": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.stateReason": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject": (v125/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isDraft": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isInMergeQueue": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.number": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.name": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.login": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.state": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.title": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target": (v125/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__isNode": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__typename": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository.id": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.url": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanBlockFromOrg": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanDelete": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanMinimize": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReadUserContentEdits": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReport": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReportToMaintainer": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUnblockFromOrg": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUndo": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUpdate": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerDidAuthor": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseSubject": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseTarget": (v104/*: any*/),
        "repository.issue.backTimelineItems.pageInfo": (v140/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.hasPreviousPage": (v104/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.startCursor": (v98/*: any*/),
        "repository.issue.backTimelineItems.totalCount": (v112/*: any*/),
        "repository.issue.body": (v96/*: any*/),
        "repository.issue.bodyHTML": (v110/*: any*/),
        "repository.issue.bodyVersion": (v96/*: any*/),
        "repository.issue.createdAt": (v107/*: any*/),
        "repository.issue.databaseId": (v123/*: any*/),
        "repository.issue.duplicateOf": (v95/*: any*/),
        "repository.issue.duplicateOf.id": (v93/*: any*/),
        "repository.issue.duplicateOf.number": (v112/*: any*/),
        "repository.issue.duplicateOf.repository": (v113/*: any*/),
        "repository.issue.duplicateOf.repository.id": (v93/*: any*/),
        "repository.issue.duplicateOf.repository.name": (v96/*: any*/),
        "repository.issue.duplicateOf.repository.owner": (v114/*: any*/),
        "repository.issue.duplicateOf.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.duplicateOf.repository.owner.id": (v93/*: any*/),
        "repository.issue.duplicateOf.repository.owner.login": (v96/*: any*/),
        "repository.issue.duplicateOf.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.cursor": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node": (v102/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isComment": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isIssueTimelineItems": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isReactable": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isTimelineEvent": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__isActor": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.avatarUrl": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.isCopilot": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.avatarUrl": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorAssociation": (v105/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v106/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v107/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockDuration": (v108/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser": (v109/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.body": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyVersion": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical": (v111/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isDraft": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isInMergeQueue": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.issueTitleHTML": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.pullTitleHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.isPrivate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.state": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.stateReason": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.abbreviatedOid": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.title": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closingProjectItemStatus": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.abbreviatedOid": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.hasSignature": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.message": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageBodyHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageHeadlineHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.defaultBranch": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer": (v120/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.commonName": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organization": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyFingerprint": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyId": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer": (v109/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.state": (v121/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject": (v120/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.commonName": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.emailAddress": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organization": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.verificationStatus": (v122/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdAt": (v107/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdViaEmail": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.currentTitle": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.databaseId": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion": (v124/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf": (v111/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isDraft": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.state": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.stateReason": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository": (v92/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.nameWithOwner": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource": (v125/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isDraft": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isInMergeQueue": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.issueTitleHTML": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.pullTitleHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.isPrivate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.state": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.stateReason": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isHidden": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue": (v126/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.databaseId": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.locked": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType": (v127/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.color": (v129/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label": (v130/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.color": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.description": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.nameHTML": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastEditedAt": (v131/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit": (v132/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lockReason": (v133/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone": (v134/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestoneTitle": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.minimizedReason": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.databaseId": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.isDraft": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.isInMergeQueue": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.issueTitleHTML": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.pullTitleHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.isPrivate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.state": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.stateReason": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingBlock": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingMinimizeReason": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUnblock": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUndo": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType": (v127/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.color": (v129/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousStatus": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousTitle": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project": (v135/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.title": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups": (v136/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.content": (v137/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors": (v138/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes": (v139/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.referencedAt": (v107/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.databaseId": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.isPrivate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.nameWithOwner": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.slashCommandsEnabled": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.showSpammyBadge": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source": (v125/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.stateReason": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.status": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.__isReferencedSubject": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.databaseId": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.isDraft": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.isInMergeQueue": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.issueTitleHTML": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.pullTitleHTML": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.isPrivate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.state": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.stateReason": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject": (v125/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isDraft": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isInMergeQueue": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.number": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.name": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.login": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.state": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.title": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target": (v125/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__isNode": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__typename": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository.id": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.url": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanBlockFromOrg": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanDelete": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanMinimize": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReadUserContentEdits": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReport": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReportToMaintainer": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUnblockFromOrg": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUndo": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUpdate": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerDidAuthor": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseSubject": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseTarget": (v104/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo": (v140/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.endCursor": (v98/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.hasNextPage": (v104/*: any*/),
        "repository.issue.frontTimelineItems.totalCount": (v112/*: any*/),
        "repository.issue.id": (v93/*: any*/),
        "repository.issue.isPinned": (v94/*: any*/),
        "repository.issue.issueType": (v127/*: any*/),
        "repository.issue.issueType.color": (v129/*: any*/),
        "repository.issue.issueType.description": (v98/*: any*/),
        "repository.issue.issueType.id": (v93/*: any*/),
        "repository.issue.issueType.isEnabled": (v104/*: any*/),
        "repository.issue.issueType.name": (v96/*: any*/),
        "repository.issue.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "repository.issue.labels.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LabelEdge"
        },
        "repository.issue.labels.edges.cursor": (v96/*: any*/),
        "repository.issue.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "repository.issue.labels.edges.node.__typename": (v96/*: any*/),
        "repository.issue.labels.edges.node.color": (v96/*: any*/),
        "repository.issue.labels.edges.node.description": (v98/*: any*/),
        "repository.issue.labels.edges.node.id": (v93/*: any*/),
        "repository.issue.labels.edges.node.name": (v96/*: any*/),
        "repository.issue.labels.edges.node.nameHTML": (v96/*: any*/),
        "repository.issue.labels.edges.node.url": (v97/*: any*/),
        "repository.issue.labels.pageInfo": (v140/*: any*/),
        "repository.issue.labels.pageInfo.endCursor": (v98/*: any*/),
        "repository.issue.labels.pageInfo.hasNextPage": (v104/*: any*/),
        "repository.issue.linkedPullRequests": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestConnection"
        },
        "repository.issue.linkedPullRequests.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequest"
        },
        "repository.issue.linkedPullRequests.nodes.id": (v93/*: any*/),
        "repository.issue.linkedPullRequests.nodes.isDraft": (v104/*: any*/),
        "repository.issue.linkedPullRequests.nodes.number": (v112/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository": (v113/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.id": (v93/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.name": (v96/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.nameWithOwner": (v96/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner": (v114/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.id": (v93/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.login": (v96/*: any*/),
        "repository.issue.linkedPullRequests.nodes.state": (v115/*: any*/),
        "repository.issue.linkedPullRequests.nodes.url": (v97/*: any*/),
        "repository.issue.locked": (v104/*: any*/),
        "repository.issue.milestone": (v134/*: any*/),
        "repository.issue.milestone.closed": (v104/*: any*/),
        "repository.issue.milestone.closedAt": (v131/*: any*/),
        "repository.issue.milestone.dueOn": (v131/*: any*/),
        "repository.issue.milestone.id": (v93/*: any*/),
        "repository.issue.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "repository.issue.milestone.title": (v96/*: any*/),
        "repository.issue.milestone.url": (v97/*: any*/),
        "repository.issue.number": (v112/*: any*/),
        "repository.issue.pendingBlock": (v94/*: any*/),
        "repository.issue.pendingUnblock": (v94/*: any*/),
        "repository.issue.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "repository.issue.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "repository.issue.projectItemsNext.edges.cursor": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "repository.issue.projectItemsNext.edges.node.__typename": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.__isNode": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.__typename": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.color": (v141/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.id": (v93/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.name": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.optionId": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.id": (v93/*: any*/),
        "repository.issue.projectItemsNext.edges.node.isArchived": (v104/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "repository.issue.projectItemsNext.edges.node.project.__typename": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.closed": (v104/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "repository.issue.projectItemsNext.edges.node.project.field.__isNode": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.__typename": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.id": (v93/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.name": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "repository.issue.projectItemsNext.edges.node.project.field.options.color": (v141/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.description": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.id": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.name": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.nameHTML": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.optionId": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v104/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.id": (v93/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.number": (v112/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.template": (v104/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.title": (v96/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.url": (v97/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.viewerCanUpdate": (v104/*: any*/),
        "repository.issue.projectItemsNext.pageInfo": (v140/*: any*/),
        "repository.issue.projectItemsNext.pageInfo.endCursor": (v98/*: any*/),
        "repository.issue.projectItemsNext.pageInfo.hasNextPage": (v104/*: any*/),
        "repository.issue.reactionGroups": (v136/*: any*/),
        "repository.issue.reactionGroups.content": (v137/*: any*/),
        "repository.issue.reactionGroups.reactors": (v138/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes": (v139/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.__isNode": (v96/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.__typename": (v96/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.id": (v93/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.login": (v96/*: any*/),
        "repository.issue.reactionGroups.reactors.totalCount": (v112/*: any*/),
        "repository.issue.reactionGroups.viewerHasReacted": (v104/*: any*/),
        "repository.issue.repository": (v113/*: any*/),
        "repository.issue.repository.databaseId": (v123/*: any*/),
        "repository.issue.repository.id": (v93/*: any*/),
        "repository.issue.repository.isArchived": (v104/*: any*/),
        "repository.issue.repository.isPrivate": (v104/*: any*/),
        "repository.issue.repository.issueTypes": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueTypeConnection"
        },
        "repository.issue.repository.issueTypes.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTypeEdge"
        },
        "repository.issue.repository.issueTypes.edges.node": (v127/*: any*/),
        "repository.issue.repository.issueTypes.edges.node.id": (v93/*: any*/),
        "repository.issue.repository.name": (v96/*: any*/),
        "repository.issue.repository.nameWithOwner": (v96/*: any*/),
        "repository.issue.repository.owner": (v114/*: any*/),
        "repository.issue.repository.owner.__typename": (v96/*: any*/),
        "repository.issue.repository.owner.id": (v93/*: any*/),
        "repository.issue.repository.owner.login": (v96/*: any*/),
        "repository.issue.repository.owner.url": (v97/*: any*/),
        "repository.issue.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "repository.issue.repository.pinnedIssues.totalCount": (v112/*: any*/),
        "repository.issue.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "repository.issue.repository.planFeatures.maximumAssignees": (v112/*: any*/),
        "repository.issue.repository.slashCommandsEnabled": (v104/*: any*/),
        "repository.issue.repository.viewerCanInteract": (v104/*: any*/),
        "repository.issue.repository.viewerCanPinIssues": (v104/*: any*/),
        "repository.issue.repository.viewerInteractionLimitReasonHTML": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "HTML"
        },
        "repository.issue.repository.visibility": {
          "enumValues": [
            "INTERNAL",
            "PRIVATE",
            "PUBLIC"
          ],
          "nullable": false,
          "plural": false,
          "type": "RepositoryVisibility"
        },
        "repository.issue.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "repository.issue.stateReason": (v116/*: any*/),
        "repository.issue.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "repository.issue.subIssuesSummary.completed": (v112/*: any*/),
        "repository.issue.subIssuesSummary.total": (v112/*: any*/),
        "repository.issue.title": (v96/*: any*/),
        "repository.issue.titleHTML": (v96/*: any*/),
        "repository.issue.updatedAt": (v107/*: any*/),
        "repository.issue.url": (v97/*: any*/),
        "repository.issue.viewerCanAssign": (v104/*: any*/),
        "repository.issue.viewerCanComment": (v104/*: any*/),
        "repository.issue.viewerCanConvertToDiscussion": (v94/*: any*/),
        "repository.issue.viewerCanDelete": (v104/*: any*/),
        "repository.issue.viewerCanLabel": (v104/*: any*/),
        "repository.issue.viewerCanLock": (v94/*: any*/),
        "repository.issue.viewerCanSetMilestone": (v104/*: any*/),
        "repository.issue.viewerCanTransfer": (v104/*: any*/),
        "repository.issue.viewerCanType": (v94/*: any*/),
        "repository.issue.viewerCanUpdate": (v104/*: any*/),
        "repository.issue.viewerCanUpdateMetadata": (v94/*: any*/),
        "repository.issue.viewerCanUpdateNext": (v94/*: any*/),
        "repository.issue.viewerDidAuthor": (v104/*: any*/),
        "safeViewer": (v109/*: any*/),
        "safeViewer.avatarUrl": (v97/*: any*/),
        "safeViewer.enterpriseManagedEnterpriseId": (v98/*: any*/),
        "safeViewer.id": (v93/*: any*/),
        "safeViewer.isEnterpriseManagedUser": (v94/*: any*/),
        "safeViewer.login": (v96/*: any*/),
        "safeViewer.name": (v98/*: any*/)
      }
    },
    "name": "IssueViewerTestComponentViewerTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "95c730123d9b956d19be6e9cf51a9318";

export default node;
