/**
 * @generated SignedSource<<65ff9d83d8c7453da34486769c44594d>>
 * @relayHash f68e3b0fbfd13829492e175511c8a976
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f68e3b0fbfd13829492e175511c8a976

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
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v28 = {
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
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCopilot",
  "storageKey": null
},
v30 = {
  "kind": "InlineFragment",
  "selections": [
    (v29/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v31 = {
  "kind": "InlineFragment",
  "selections": (v18/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v35 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileUrl",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v39 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
},
v43 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v44 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v43/*: any*/)
],
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingBlock",
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v51 = [
  (v9/*: any*/)
],
v52 = {
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
                  "selections": (v51/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v9/*: any*/),
                    (v29/*: any*/)
                  ],
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v51/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v51/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v31/*: any*/)
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
v53 = [
  (v8/*: any*/),
  (v31/*: any*/)
],
v54 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v18/*: any*/),
  "storageKey": null
},
v55 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v56 = {
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
v57 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v55/*: any*/),
    (v10/*: any*/),
    (v5/*: any*/),
    (v22/*: any*/),
    (v56/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v58 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v60 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v58/*: any*/),
    (v10/*: any*/),
    (v5/*: any*/),
    (v21/*: any*/),
    (v26/*: any*/),
    (v59/*: any*/),
    (v56/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v61 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v35/*: any*/),
    (v28/*: any*/),
    (v9/*: any*/),
    (v27/*: any*/),
    (v30/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v62 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v63 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v62/*: any*/),
      (v7/*: any*/),
      (v19/*: any*/),
      (v20/*: any*/)
    ],
    "storageKey": null
  },
  (v13/*: any*/),
  (v47/*: any*/),
  (v61/*: any*/)
],
v64 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v65 = [
  (v9/*: any*/),
  (v64/*: any*/)
],
v66 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "assignee",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": (v18/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v18/*: any*/),
      "type": "Bot",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v18/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v18/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    (v31/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": [
        (v9/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v65/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v65/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v65/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v64/*: any*/),
            (v29/*: any*/)
          ],
          "type": "Bot",
          "abstractKey": null
        }
      ],
      "type": "Actor",
      "abstractKey": "__isActor"
    }
  ],
  "storageKey": null
},
v67 = [
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
  (v47/*: any*/),
  (v61/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v68 = [
  (v47/*: any*/),
  (v13/*: any*/),
  (v61/*: any*/)
],
v69 = {
  "kind": "InlineFragment",
  "selections": [
    (v57/*: any*/),
    (v60/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v70 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v71 = [
  (v13/*: any*/),
  (v47/*: any*/),
  (v61/*: any*/)
],
v72 = [
  (v13/*: any*/),
  (v61/*: any*/),
  (v47/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v13/*: any*/),
      (v3/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v8/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v55/*: any*/),
              (v10/*: any*/),
              (v5/*: any*/),
              (v22/*: any*/),
              (v56/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v58/*: any*/),
              (v10/*: any*/),
              (v5/*: any*/),
              (v21/*: any*/),
              (v26/*: any*/),
              (v59/*: any*/),
              (v56/*: any*/)
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "type": "ReferencedSubject",
        "abstractKey": "__isReferencedSubject"
      }
    ],
    "storageKey": null
  }
],
v73 = {
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
v74 = [
  (v13/*: any*/),
  (v61/*: any*/),
  (v47/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v54/*: any*/),
      (v13/*: any*/),
      (v3/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v8/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v55/*: any*/),
              (v10/*: any*/),
              (v5/*: any*/),
              (v22/*: any*/),
              (v73/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v58/*: any*/),
              (v10/*: any*/),
              (v5/*: any*/),
              (v21/*: any*/),
              (v26/*: any*/),
              (v59/*: any*/),
              (v73/*: any*/)
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "type": "ReferencedSubject",
        "abstractKey": "__isReferencedSubject"
      }
    ],
    "storageKey": null
  }
],
v75 = [
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
v76 = [
  (v13/*: any*/),
  (v61/*: any*/),
  (v47/*: any*/),
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
          (v59/*: any*/),
          (v25/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v31/*: any*/)
    ],
    "storageKey": null
  }
],
v77 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v55/*: any*/),
        (v10/*: any*/),
        (v22/*: any*/),
        (v56/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v58/*: any*/),
        (v10/*: any*/),
        (v21/*: any*/),
        (v26/*: any*/),
        (v59/*: any*/),
        (v56/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v78 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v79 = [
  (v69/*: any*/)
],
v80 = {
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
v81 = [
  (v7/*: any*/),
  (v19/*: any*/),
  (v3/*: any*/)
],
v82 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v81/*: any*/),
  "storageKey": null
},
v83 = [
  (v13/*: any*/),
  (v61/*: any*/),
  (v47/*: any*/),
  (v82/*: any*/)
],
v84 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v85 = {
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
            (v47/*: any*/),
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
            (v33/*: any*/),
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
                (v34/*: any*/),
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
                (v37/*: any*/),
                (v36/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            },
            (v3/*: any*/),
            (v38/*: any*/),
            {
              "alias": null,
              "args": [
                (v39/*: any*/)
              ],
              "kind": "ScalarField",
              "name": "bodyHTML",
              "storageKey": "bodyHTML(unfurlReferences:true)"
            },
            (v40/*: any*/),
            (v48/*: any*/),
            (v10/*: any*/),
            (v47/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "authorAssociation",
              "storageKey": null
            },
            (v41/*: any*/),
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
                (v47/*: any*/),
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
                (v49/*: any*/),
                (v50/*: any*/)
              ]
            },
            (v52/*: any*/)
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
              "selections": (v53/*: any*/),
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
                    (v54/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v31/*: any*/)
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
                (v57/*: any*/),
                (v60/*: any*/),
                (v31/*: any*/)
              ],
              "storageKey": null
            },
            (v61/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v63/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v63/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v66/*: any*/),
            (v13/*: any*/),
            (v47/*: any*/),
            (v61/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v66/*: any*/),
            (v13/*: any*/),
            (v47/*: any*/),
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
                (v35/*: any*/),
                (v28/*: any*/),
                (v27/*: any*/),
                (v30/*: any*/),
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
          "selections": (v67/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v68/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v47/*: any*/),
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
                (v69/*: any*/),
                (v31/*: any*/)
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
                    (v70/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v31/*: any*/)
              ],
              "storageKey": null
            },
            (v61/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v47/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v61/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v47/*: any*/),
            (v61/*: any*/),
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
            (v47/*: any*/),
            (v61/*: any*/),
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
            (v47/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v61/*: any*/),
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
          "selections": (v72/*: any*/),
          "type": "SubIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v72/*: any*/),
          "type": "SubIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v74/*: any*/),
          "type": "ParentIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v74/*: any*/),
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
              "selections": (v53/*: any*/),
              "storageKey": null
            },
            (v61/*: any*/),
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
                (v70/*: any*/),
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
                        (v37/*: any*/),
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
                          "selections": (v75/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v75/*: any*/),
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
            (v47/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v76/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v61/*: any*/),
            (v47/*: any*/),
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
          "selections": (v76/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v61/*: any*/),
            (v47/*: any*/),
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
                    (v77/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v5/*: any*/),
                    (v3/*: any*/),
                    (v77/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v31/*: any*/)
              ],
              "storageKey": null
            },
            (v78/*: any*/),
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
            (v61/*: any*/),
            (v47/*: any*/),
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
                  "selections": (v79/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v79/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v31/*: any*/)
              ],
              "storageKey": null
            },
            (v78/*: any*/),
            (v13/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v61/*: any*/),
            (v47/*: any*/),
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
            (v47/*: any*/),
            (v61/*: any*/),
            (v80/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v47/*: any*/),
            (v61/*: any*/),
            (v80/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v47/*: any*/),
            (v61/*: any*/),
            (v80/*: any*/),
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
            (v47/*: any*/),
            (v61/*: any*/),
            (v13/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v83/*: any*/),
          "type": "IssueTypeAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v83/*: any*/),
          "type": "IssueTypeRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v61/*: any*/),
            (v47/*: any*/),
            (v82/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "prevIssueType",
              "plural": false,
              "selections": (v81/*: any*/),
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
        (v31/*: any*/)
      ],
      "storageKey": null
    },
    (v84/*: any*/)
  ],
  "storageKey": null
},
v86 = [
  "visibleEventsOnly"
],
v87 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v43/*: any*/)
],
v88 = [
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
v89 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v46/*: any*/),
    (v45/*: any*/)
  ],
  "storageKey": null
},
v90 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v91 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v92 = {
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
                (v48/*: any*/),
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": (v90/*: any*/),
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
                            (v91/*: any*/),
                            (v7/*: any*/),
                            (v62/*: any*/),
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
                    (v31/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v32/*: any*/),
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
              "args": (v90/*: any*/),
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
                    (v91/*: any*/),
                    (v7/*: any*/),
                    (v62/*: any*/),
                    (v19/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v31/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v8/*: any*/)
          ],
          "storageKey": null
        },
        (v84/*: any*/)
      ],
      "storageKey": null
    },
    (v89/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v93 = {
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
v94 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v95 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v96 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v97 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v98 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v99 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v100 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v101 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v102 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v103 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v104 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v105 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v106 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v107 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
},
v108 = {
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
v109 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Sponsorship"
},
v110 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v111 = {
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
v112 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v113 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v114 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v115 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v116 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v117 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v118 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v119 = {
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
v120 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v121 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v122 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitSignature"
},
v123 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v124 = {
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
v125 = {
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
v126 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v127 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Discussion"
},
v128 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v129 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v130 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v131 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v132 = {
  "enumValues": (v131/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
},
v133 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v134 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v135 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v136 = {
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
v137 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
},
v138 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "ProjectV2"
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
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v144 = {
  "enumValues": (v131/*: any*/),
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
                "concreteType": "AssigneeConnection",
                "kind": "LinkedField",
                "name": "assignedActors",
                "plural": false,
                "selections": [
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
                        "selections": [
                          (v3/*: any*/),
                          (v9/*: any*/),
                          (v7/*: any*/),
                          (v27/*: any*/),
                          (v28/*: any*/),
                          (v30/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      (v31/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "assignedActors(first:20)"
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
                  (v32/*: any*/),
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
              (v33/*: any*/),
              (v34/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v8/*: any*/),
                  (v35/*: any*/),
                  (v9/*: any*/),
                  (v3/*: any*/),
                  (v36/*: any*/),
                  (v37/*: any*/)
                ],
                "storageKey": null
              },
              (v38/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v39/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v40/*: any*/),
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
              (v41/*: any*/),
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
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 25
                  }
                ],
                "concreteType": "IssueFieldValueConnection",
                "kind": "LinkedField",
                "name": "issueFieldValues",
                "plural": false,
                "selections": [
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
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
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
                                  (v42/*: any*/)
                                ],
                                "type": "IssueFieldText",
                                "abstractKey": null
                              },
                              (v31/*: any*/)
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "value",
                            "storageKey": null
                          }
                        ],
                        "type": "IssueFieldTextValue",
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
                            "name": "field",
                            "plural": false,
                            "selections": [
                              (v8/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v7/*: any*/),
                                  (v42/*: any*/)
                                ],
                                "type": "IssueFieldSingleSelect",
                                "abstractKey": null
                              },
                              (v31/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v7/*: any*/),
                          (v19/*: any*/),
                          (v20/*: any*/)
                        ],
                        "type": "IssueFieldSingleSelectValue",
                        "abstractKey": null
                      },
                      (v31/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "issueFieldValues(first:25)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v44/*: any*/),
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
                      (v45/*: any*/),
                      (v46/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v15/*: any*/),
                  (v85/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v44/*: any*/),
                "filters": (v86/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v87/*: any*/),
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
                  (v85/*: any*/)
                ],
                "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v87/*: any*/),
                "filters": (v86/*: any*/),
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
                    "args": (v88/*: any*/),
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
                              (v62/*: any*/),
                              (v20/*: any*/),
                              (v10/*: any*/),
                              (v8/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v84/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v89/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v88/*: any*/),
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
                  (v47/*: any*/)
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v52/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v49/*: any*/),
                  (v50/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v92/*: any*/),
                      (v93/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v92/*: any*/),
                      (v93/*: any*/),
                      (v48/*: any*/)
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
          (v28/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v8/*: any*/),
              (v7/*: any*/),
              (v27/*: any*/),
              (v30/*: any*/)
            ],
            "type": "Actor",
            "abstractKey": "__isActor"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "f68e3b0fbfd13829492e175511c8a976",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": (v94/*: any*/),
        "repository.id": (v95/*: any*/),
        "repository.isOwnerEnterpriseManaged": (v96/*: any*/),
        "repository.issue": (v97/*: any*/),
        "repository.issue.__isComment": (v98/*: any*/),
        "repository.issue.__isIssueOrPullRequest": (v98/*: any*/),
        "repository.issue.__isLabelable": (v98/*: any*/),
        "repository.issue.__isNode": (v98/*: any*/),
        "repository.issue.__isReactable": (v98/*: any*/),
        "repository.issue.assignedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "repository.issue.assignedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "repository.issue.assignedActors.nodes.__isActor": (v98/*: any*/),
        "repository.issue.assignedActors.nodes.__isNode": (v98/*: any*/),
        "repository.issue.assignedActors.nodes.__typename": (v98/*: any*/),
        "repository.issue.assignedActors.nodes.avatarUrl": (v99/*: any*/),
        "repository.issue.assignedActors.nodes.id": (v95/*: any*/),
        "repository.issue.assignedActors.nodes.isCopilot": (v100/*: any*/),
        "repository.issue.assignedActors.nodes.login": (v98/*: any*/),
        "repository.issue.assignedActors.nodes.name": (v101/*: any*/),
        "repository.issue.assignedActors.nodes.profileResourcePath": (v102/*: any*/),
        "repository.issue.author": (v103/*: any*/),
        "repository.issue.author.__isActor": (v98/*: any*/),
        "repository.issue.author.__typename": (v98/*: any*/),
        "repository.issue.author.avatarUrl": (v99/*: any*/),
        "repository.issue.author.id": (v95/*: any*/),
        "repository.issue.author.login": (v98/*: any*/),
        "repository.issue.author.profileUrl": (v102/*: any*/),
        "repository.issue.backTimelineItems": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges": (v105/*: any*/),
        "repository.issue.backTimelineItems.edges.cursor": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node": (v106/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isComment": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isIssueTimelineItems": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isReactable": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isTimelineEvent": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__isActor": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.avatarUrl": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.isCopilot": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.profileResourcePath": (v102/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee": (v107/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__isActor": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.isCopilot": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.resourcePath": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.avatarUrl": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.profileUrl": (v102/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorAssociation": (v108/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v109/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockDuration": (v111/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.body": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyVersion": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isDraft": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isInMergeQueue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.issueTitleHTML": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.pullTitleHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.isPrivate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.state": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.stateReason": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer": (v120/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.abbreviatedOid": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.title": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closingProjectItemStatus": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit": (v121/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.abbreviatedOid": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.hasSignature": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.message": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageBodyHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageHeadlineHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.defaultBranch": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature": (v122/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.commonName": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organization": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyFingerprint": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyId": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.state": (v124/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject": (v123/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.commonName": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.emailAddress": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organization": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.verificationStatus": (v125/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdAt": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdViaEmail": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.currentTitle": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.databaseId": (v126/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion": (v127/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf": (v114/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isDraft": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.state": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.stateReason": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.nameWithOwner": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource": (v128/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isDraft": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isInMergeQueue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.issueTitleHTML": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.pullTitleHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.isPrivate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.state": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.stateReason": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isHidden": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue": (v129/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.databaseId": (v126/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.locked": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType": (v130/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.color": (v132/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label": (v133/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.color": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.description": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.nameHTML": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastEditedAt": (v134/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit": (v135/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lockReason": (v136/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone": (v137/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestoneTitle": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.minimizedReason": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.databaseId": (v126/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.isDraft": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.isInMergeQueue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.issueTitleHTML": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.pullTitleHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.isPrivate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.state": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.stateReason": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingBlock": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingMinimizeReason": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUnblock": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUndo": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType": (v130/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.color": (v132/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousStatus": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousTitle": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project": (v138/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.title": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups": (v139/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.content": (v140/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.isCopilot": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.referencedAt": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.databaseId": (v126/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.isPrivate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.nameWithOwner": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.slashCommandsEnabled": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.showSpammyBadge": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source": (v128/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.stateReason": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.status": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.databaseId": (v126/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.isDraft": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.isInMergeQueue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.issueTitleHTML": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.pullTitleHTML": (v113/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.isPrivate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.state": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.stateReason": (v119/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject": (v128/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isDraft": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isInMergeQueue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.number": (v115/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.name": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner": (v117/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.login": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.state": (v118/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.title": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target": (v128/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__isNode": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__typename": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository": (v116/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository.id": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.url": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanBlockFromOrg": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanDelete": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanMinimize": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReadUserContentEdits": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReport": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReportToMaintainer": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUnblockFromOrg": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUndo": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUpdate": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerDidAuthor": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseSubject": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseTarget": (v100/*: any*/),
        "repository.issue.backTimelineItems.pageInfo": (v143/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.hasPreviousPage": (v100/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.startCursor": (v101/*: any*/),
        "repository.issue.backTimelineItems.totalCount": (v115/*: any*/),
        "repository.issue.body": (v98/*: any*/),
        "repository.issue.bodyHTML": (v113/*: any*/),
        "repository.issue.bodyVersion": (v98/*: any*/),
        "repository.issue.createdAt": (v110/*: any*/),
        "repository.issue.databaseId": (v126/*: any*/),
        "repository.issue.duplicateOf": (v97/*: any*/),
        "repository.issue.duplicateOf.id": (v95/*: any*/),
        "repository.issue.duplicateOf.number": (v115/*: any*/),
        "repository.issue.duplicateOf.repository": (v116/*: any*/),
        "repository.issue.duplicateOf.repository.id": (v95/*: any*/),
        "repository.issue.duplicateOf.repository.name": (v98/*: any*/),
        "repository.issue.duplicateOf.repository.owner": (v117/*: any*/),
        "repository.issue.duplicateOf.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.duplicateOf.repository.owner.id": (v95/*: any*/),
        "repository.issue.duplicateOf.repository.owner.login": (v98/*: any*/),
        "repository.issue.duplicateOf.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges": (v105/*: any*/),
        "repository.issue.frontTimelineItems.edges.cursor": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node": (v106/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isComment": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isIssueTimelineItems": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isReactable": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isTimelineEvent": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__isActor": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.avatarUrl": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.isCopilot": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.profileResourcePath": (v102/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee": (v107/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__isActor": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.isCopilot": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.resourcePath": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.avatarUrl": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.profileUrl": (v102/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorAssociation": (v108/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v109/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockDuration": (v111/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.body": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyVersion": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isDraft": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isInMergeQueue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.issueTitleHTML": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.pullTitleHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.isPrivate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.state": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.stateReason": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer": (v120/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.abbreviatedOid": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.title": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closingProjectItemStatus": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit": (v121/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.abbreviatedOid": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.hasSignature": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.message": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageBodyHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageHeadlineHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.defaultBranch": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature": (v122/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.commonName": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organization": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyFingerprint": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyId": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.state": (v124/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject": (v123/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.commonName": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.emailAddress": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organization": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.verificationStatus": (v125/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdAt": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdViaEmail": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.currentTitle": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.databaseId": (v126/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion": (v127/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf": (v114/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isDraft": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.state": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.stateReason": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.nameWithOwner": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource": (v128/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isDraft": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isInMergeQueue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.issueTitleHTML": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.pullTitleHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.isPrivate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.state": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.stateReason": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isHidden": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue": (v129/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.databaseId": (v126/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.locked": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType": (v130/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.color": (v132/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label": (v133/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.color": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.description": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.nameHTML": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastEditedAt": (v134/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit": (v135/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lockReason": (v136/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone": (v137/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestoneTitle": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.minimizedReason": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.databaseId": (v126/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.isDraft": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.isInMergeQueue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.issueTitleHTML": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.pullTitleHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.isPrivate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.state": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.stateReason": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingBlock": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingMinimizeReason": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUnblock": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUndo": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType": (v130/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.color": (v132/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousStatus": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousTitle": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project": (v138/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.title": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups": (v139/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.content": (v140/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.isCopilot": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.referencedAt": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.databaseId": (v126/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.isPrivate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.nameWithOwner": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.slashCommandsEnabled": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.showSpammyBadge": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source": (v128/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.stateReason": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.status": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.__isReferencedSubject": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.databaseId": (v126/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.isDraft": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.isInMergeQueue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.issueTitleHTML": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.pullTitleHTML": (v113/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.isPrivate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.state": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.stateReason": (v119/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject": (v128/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isDraft": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isInMergeQueue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.number": (v115/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.name": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner": (v117/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.login": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.state": (v118/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.title": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target": (v128/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__isNode": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__typename": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository": (v116/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository.id": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.url": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanBlockFromOrg": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanDelete": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanMinimize": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReadUserContentEdits": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReport": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReportToMaintainer": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUnblockFromOrg": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUndo": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUpdate": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerDidAuthor": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseSubject": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseTarget": (v100/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo": (v143/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.endCursor": (v101/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.hasNextPage": (v100/*: any*/),
        "repository.issue.frontTimelineItems.totalCount": (v115/*: any*/),
        "repository.issue.id": (v95/*: any*/),
        "repository.issue.isPinned": (v96/*: any*/),
        "repository.issue.issueFieldValues": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFieldValueConnection"
        },
        "repository.issue.issueFieldValues.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueFieldValue"
        },
        "repository.issue.issueFieldValues.nodes.__isNode": (v98/*: any*/),
        "repository.issue.issueFieldValues.nodes.__typename": (v98/*: any*/),
        "repository.issue.issueFieldValues.nodes.color": {
          "enumValues": (v131/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueFieldSingleSelectOptionColor"
        },
        "repository.issue.issueFieldValues.nodes.description": (v101/*: any*/),
        "repository.issue.issueFieldValues.nodes.field": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFields"
        },
        "repository.issue.issueFieldValues.nodes.field.__isNode": (v98/*: any*/),
        "repository.issue.issueFieldValues.nodes.field.__typename": (v98/*: any*/),
        "repository.issue.issueFieldValues.nodes.field.dataType": {
          "enumValues": [
            "SINGLE_SELECT",
            "TEXT"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueFieldDataType"
        },
        "repository.issue.issueFieldValues.nodes.field.id": (v95/*: any*/),
        "repository.issue.issueFieldValues.nodes.field.name": (v98/*: any*/),
        "repository.issue.issueFieldValues.nodes.id": (v95/*: any*/),
        "repository.issue.issueFieldValues.nodes.name": (v98/*: any*/),
        "repository.issue.issueFieldValues.nodes.value": (v98/*: any*/),
        "repository.issue.issueType": (v130/*: any*/),
        "repository.issue.issueType.color": (v132/*: any*/),
        "repository.issue.issueType.description": (v101/*: any*/),
        "repository.issue.issueType.id": (v95/*: any*/),
        "repository.issue.issueType.isEnabled": (v100/*: any*/),
        "repository.issue.issueType.name": (v98/*: any*/),
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
        "repository.issue.labels.edges.cursor": (v98/*: any*/),
        "repository.issue.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "repository.issue.labels.edges.node.__typename": (v98/*: any*/),
        "repository.issue.labels.edges.node.color": (v98/*: any*/),
        "repository.issue.labels.edges.node.description": (v101/*: any*/),
        "repository.issue.labels.edges.node.id": (v95/*: any*/),
        "repository.issue.labels.edges.node.name": (v98/*: any*/),
        "repository.issue.labels.edges.node.nameHTML": (v98/*: any*/),
        "repository.issue.labels.edges.node.url": (v99/*: any*/),
        "repository.issue.labels.pageInfo": (v143/*: any*/),
        "repository.issue.labels.pageInfo.endCursor": (v101/*: any*/),
        "repository.issue.labels.pageInfo.hasNextPage": (v100/*: any*/),
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
        "repository.issue.linkedPullRequests.nodes.id": (v95/*: any*/),
        "repository.issue.linkedPullRequests.nodes.isDraft": (v100/*: any*/),
        "repository.issue.linkedPullRequests.nodes.number": (v115/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository": (v116/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.id": (v95/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.name": (v98/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.nameWithOwner": (v98/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner": (v117/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.id": (v95/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.login": (v98/*: any*/),
        "repository.issue.linkedPullRequests.nodes.state": (v118/*: any*/),
        "repository.issue.linkedPullRequests.nodes.url": (v99/*: any*/),
        "repository.issue.locked": (v100/*: any*/),
        "repository.issue.milestone": (v137/*: any*/),
        "repository.issue.milestone.closed": (v100/*: any*/),
        "repository.issue.milestone.closedAt": (v134/*: any*/),
        "repository.issue.milestone.dueOn": (v134/*: any*/),
        "repository.issue.milestone.id": (v95/*: any*/),
        "repository.issue.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "repository.issue.milestone.title": (v98/*: any*/),
        "repository.issue.milestone.url": (v99/*: any*/),
        "repository.issue.number": (v115/*: any*/),
        "repository.issue.pendingBlock": (v96/*: any*/),
        "repository.issue.pendingUnblock": (v96/*: any*/),
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
        "repository.issue.projectItemsNext.edges.cursor": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "repository.issue.projectItemsNext.edges.node.__typename": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.__isNode": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.__typename": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.color": (v144/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.id": (v95/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.name": (v101/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v101/*: any*/),
        "repository.issue.projectItemsNext.edges.node.fieldValueByName.optionId": (v101/*: any*/),
        "repository.issue.projectItemsNext.edges.node.id": (v95/*: any*/),
        "repository.issue.projectItemsNext.edges.node.isArchived": (v100/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "repository.issue.projectItemsNext.edges.node.project.__typename": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.closed": (v100/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "repository.issue.projectItemsNext.edges.node.project.field.__isNode": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.__typename": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.id": (v95/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.name": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "repository.issue.projectItemsNext.edges.node.project.field.options.color": (v144/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.description": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.id": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.name": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.nameHTML": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.field.options.optionId": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v100/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.id": (v95/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.number": (v115/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.template": (v100/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.title": (v98/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.url": (v99/*: any*/),
        "repository.issue.projectItemsNext.edges.node.project.viewerCanUpdate": (v100/*: any*/),
        "repository.issue.projectItemsNext.pageInfo": (v143/*: any*/),
        "repository.issue.projectItemsNext.pageInfo.endCursor": (v101/*: any*/),
        "repository.issue.projectItemsNext.pageInfo.hasNextPage": (v100/*: any*/),
        "repository.issue.reactionGroups": (v139/*: any*/),
        "repository.issue.reactionGroups.content": (v140/*: any*/),
        "repository.issue.reactionGroups.reactors": (v141/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes": (v142/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.__isNode": (v98/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.__typename": (v98/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.id": (v95/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.isCopilot": (v100/*: any*/),
        "repository.issue.reactionGroups.reactors.nodes.login": (v98/*: any*/),
        "repository.issue.reactionGroups.reactors.totalCount": (v115/*: any*/),
        "repository.issue.reactionGroups.viewerHasReacted": (v100/*: any*/),
        "repository.issue.repository": (v116/*: any*/),
        "repository.issue.repository.databaseId": (v126/*: any*/),
        "repository.issue.repository.id": (v95/*: any*/),
        "repository.issue.repository.isArchived": (v100/*: any*/),
        "repository.issue.repository.isPrivate": (v100/*: any*/),
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
        "repository.issue.repository.issueTypes.edges.node": (v130/*: any*/),
        "repository.issue.repository.issueTypes.edges.node.id": (v95/*: any*/),
        "repository.issue.repository.name": (v98/*: any*/),
        "repository.issue.repository.nameWithOwner": (v98/*: any*/),
        "repository.issue.repository.owner": (v117/*: any*/),
        "repository.issue.repository.owner.__typename": (v98/*: any*/),
        "repository.issue.repository.owner.id": (v95/*: any*/),
        "repository.issue.repository.owner.login": (v98/*: any*/),
        "repository.issue.repository.owner.url": (v99/*: any*/),
        "repository.issue.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "repository.issue.repository.pinnedIssues.totalCount": (v115/*: any*/),
        "repository.issue.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "repository.issue.repository.planFeatures.maximumAssignees": (v115/*: any*/),
        "repository.issue.repository.slashCommandsEnabled": (v100/*: any*/),
        "repository.issue.repository.viewerCanInteract": (v100/*: any*/),
        "repository.issue.repository.viewerCanPinIssues": (v100/*: any*/),
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
        "repository.issue.stateReason": (v119/*: any*/),
        "repository.issue.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "repository.issue.subIssuesSummary.completed": (v115/*: any*/),
        "repository.issue.subIssuesSummary.total": (v115/*: any*/),
        "repository.issue.title": (v98/*: any*/),
        "repository.issue.titleHTML": (v98/*: any*/),
        "repository.issue.updatedAt": (v110/*: any*/),
        "repository.issue.url": (v99/*: any*/),
        "repository.issue.viewerCanAssign": (v100/*: any*/),
        "repository.issue.viewerCanComment": (v100/*: any*/),
        "repository.issue.viewerCanConvertToDiscussion": (v96/*: any*/),
        "repository.issue.viewerCanDelete": (v100/*: any*/),
        "repository.issue.viewerCanLabel": (v100/*: any*/),
        "repository.issue.viewerCanLock": (v96/*: any*/),
        "repository.issue.viewerCanSetMilestone": (v100/*: any*/),
        "repository.issue.viewerCanTransfer": (v100/*: any*/),
        "repository.issue.viewerCanType": (v96/*: any*/),
        "repository.issue.viewerCanUpdate": (v100/*: any*/),
        "repository.issue.viewerCanUpdateMetadata": (v96/*: any*/),
        "repository.issue.viewerCanUpdateNext": (v96/*: any*/),
        "repository.issue.viewerDidAuthor": (v100/*: any*/),
        "safeViewer": (v112/*: any*/),
        "safeViewer.__isActor": (v98/*: any*/),
        "safeViewer.__typename": (v98/*: any*/),
        "safeViewer.avatarUrl": (v99/*: any*/),
        "safeViewer.enterpriseManagedEnterpriseId": (v101/*: any*/),
        "safeViewer.id": (v95/*: any*/),
        "safeViewer.isCopilot": (v100/*: any*/),
        "safeViewer.isEnterpriseManagedUser": (v96/*: any*/),
        "safeViewer.login": (v98/*: any*/),
        "safeViewer.name": (v101/*: any*/),
        "safeViewer.profileResourcePath": (v102/*: any*/)
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
