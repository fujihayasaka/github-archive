/**
 * @generated SignedSource<<312d79b1fcf31441c2e938fd00677d9f>>
 * @relayHash 40636c53042501c9712d6410524aa9be
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 40636c53042501c9712d6410524aa9be

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
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
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
  "name": "isCopilot",
  "storageKey": null
},
v29 = {
  "kind": "InlineFragment",
  "selections": [
    (v28/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v30 = {
  "kind": "InlineFragment",
  "selections": (v17/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
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
  "name": "locked",
  "storageKey": null
},
v34 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileUrl",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v38 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
},
v42 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v43 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v42/*: any*/)
],
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingBlock",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v50 = [
  (v8/*: any*/)
],
v51 = {
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
                  "selections": (v50/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v8/*: any*/),
                    (v28/*: any*/)
                  ],
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v50/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v50/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v30/*: any*/)
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
v52 = [
  (v2/*: any*/),
  (v30/*: any*/)
],
v53 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v17/*: any*/),
  "storageKey": null
},
v54 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v55 = {
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
v56 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v54/*: any*/),
    (v9/*: any*/),
    (v5/*: any*/),
    (v21/*: any*/),
    (v55/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v57 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v58 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v59 = {
  "kind": "InlineFragment",
  "selections": [
    (v3/*: any*/),
    (v57/*: any*/),
    (v9/*: any*/),
    (v5/*: any*/),
    (v20/*: any*/),
    (v25/*: any*/),
    (v58/*: any*/),
    (v55/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v60 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v34/*: any*/),
    (v27/*: any*/),
    (v8/*: any*/),
    (v26/*: any*/),
    (v29/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v61 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v62 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v61/*: any*/),
      (v7/*: any*/),
      (v18/*: any*/),
      (v19/*: any*/)
    ],
    "storageKey": null
  },
  (v12/*: any*/),
  (v46/*: any*/),
  (v60/*: any*/)
],
v63 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v64 = [
  (v8/*: any*/),
  (v63/*: any*/)
],
v65 = {
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
      "selections": (v17/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v17/*: any*/),
      "type": "Bot",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v17/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v17/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    (v30/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": [
        (v8/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v64/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v8/*: any*/),
            (v63/*: any*/),
            (v28/*: any*/)
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
v66 = [
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
  (v46/*: any*/),
  (v60/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v67 = [
  (v46/*: any*/),
  (v12/*: any*/),
  (v60/*: any*/)
],
v68 = {
  "kind": "InlineFragment",
  "selections": [
    (v56/*: any*/),
    (v59/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v69 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v70 = [
  (v12/*: any*/),
  (v46/*: any*/),
  (v60/*: any*/)
],
v71 = [
  (v12/*: any*/),
  (v60/*: any*/),
  (v46/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v12/*: any*/),
      (v3/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v54/*: any*/),
              (v9/*: any*/),
              (v5/*: any*/),
              (v21/*: any*/),
              (v55/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v57/*: any*/),
              (v9/*: any*/),
              (v5/*: any*/),
              (v20/*: any*/),
              (v25/*: any*/),
              (v58/*: any*/),
              (v55/*: any*/)
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
v72 = {
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
v73 = [
  (v12/*: any*/),
  (v60/*: any*/),
  (v46/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v53/*: any*/),
      (v12/*: any*/),
      (v3/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v54/*: any*/),
              (v9/*: any*/),
              (v5/*: any*/),
              (v21/*: any*/),
              (v72/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v57/*: any*/),
              (v9/*: any*/),
              (v5/*: any*/),
              (v20/*: any*/),
              (v25/*: any*/),
              (v58/*: any*/),
              (v72/*: any*/)
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
v74 = [
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
v75 = [
  (v12/*: any*/),
  (v60/*: any*/),
  (v46/*: any*/),
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
          (v58/*: any*/),
          (v24/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v30/*: any*/)
    ],
    "storageKey": null
  }
],
v76 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v54/*: any*/),
        (v9/*: any*/),
        (v21/*: any*/),
        (v55/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v57/*: any*/),
        (v9/*: any*/),
        (v20/*: any*/),
        (v25/*: any*/),
        (v58/*: any*/),
        (v55/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v77 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v78 = [
  (v68/*: any*/)
],
v79 = {
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
v80 = [
  (v7/*: any*/),
  (v18/*: any*/),
  (v3/*: any*/)
],
v81 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v80/*: any*/),
  "storageKey": null
},
v82 = [
  (v12/*: any*/),
  (v60/*: any*/),
  (v46/*: any*/),
  (v81/*: any*/)
],
v83 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v84 = {
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
            (v46/*: any*/),
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
            (v32/*: any*/),
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
                (v33/*: any*/),
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
                (v36/*: any*/),
                (v35/*: any*/),
                (v3/*: any*/)
              ],
              "storageKey": null
            },
            (v3/*: any*/),
            (v37/*: any*/),
            {
              "alias": null,
              "args": [
                (v38/*: any*/)
              ],
              "kind": "ScalarField",
              "name": "bodyHTML",
              "storageKey": "bodyHTML(unfurlReferences:true)"
            },
            (v39/*: any*/),
            (v47/*: any*/),
            (v9/*: any*/),
            (v46/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "authorAssociation",
              "storageKey": null
            },
            (v40/*: any*/),
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
                (v46/*: any*/),
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
                (v48/*: any*/),
                (v49/*: any*/)
              ]
            },
            (v51/*: any*/)
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
              "selections": (v52/*: any*/),
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
                    (v53/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v30/*: any*/)
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
                (v56/*: any*/),
                (v59/*: any*/),
                (v30/*: any*/)
              ],
              "storageKey": null
            },
            (v60/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v62/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v62/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v65/*: any*/),
            (v12/*: any*/),
            (v46/*: any*/),
            (v60/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v65/*: any*/),
            (v12/*: any*/),
            (v46/*: any*/),
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
                (v34/*: any*/),
                (v27/*: any*/),
                (v26/*: any*/),
                (v29/*: any*/),
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
          "selections": (v66/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v66/*: any*/),
          "type": "DemilestonedEvent",
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
          "selections": (v67/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v46/*: any*/),
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
                (v68/*: any*/),
                (v30/*: any*/)
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
                    (v69/*: any*/),
                    (v24/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v30/*: any*/)
              ],
              "storageKey": null
            },
            (v60/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v46/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v60/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v70/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v46/*: any*/),
            (v60/*: any*/),
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
            (v46/*: any*/),
            (v60/*: any*/),
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
            (v46/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v60/*: any*/),
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
          "selections": (v73/*: any*/),
          "type": "ParentIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v73/*: any*/),
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
              "selections": (v52/*: any*/),
              "storageKey": null
            },
            (v60/*: any*/),
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
                (v69/*: any*/),
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
                        (v36/*: any*/),
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
                          "selections": (v74/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v74/*: any*/),
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
            (v46/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v75/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v60/*: any*/),
            (v46/*: any*/),
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
          "selections": (v75/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v60/*: any*/),
            (v46/*: any*/),
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
                    (v76/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v5/*: any*/),
                    (v3/*: any*/),
                    (v76/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v30/*: any*/)
              ],
              "storageKey": null
            },
            (v77/*: any*/),
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
            (v60/*: any*/),
            (v46/*: any*/),
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
                  "selections": (v78/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v78/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v30/*: any*/)
              ],
              "storageKey": null
            },
            (v77/*: any*/),
            (v12/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v60/*: any*/),
            (v46/*: any*/),
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
            (v46/*: any*/),
            (v60/*: any*/),
            (v79/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v46/*: any*/),
            (v60/*: any*/),
            (v79/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v46/*: any*/),
            (v60/*: any*/),
            (v79/*: any*/),
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
            (v46/*: any*/),
            (v60/*: any*/),
            (v12/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v82/*: any*/),
          "type": "IssueTypeAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v82/*: any*/),
          "type": "IssueTypeRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v12/*: any*/),
            (v60/*: any*/),
            (v46/*: any*/),
            (v81/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "prevIssueType",
              "plural": false,
              "selections": (v80/*: any*/),
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
        (v30/*: any*/)
      ],
      "storageKey": null
    },
    (v83/*: any*/)
  ],
  "storageKey": null
},
v85 = [
  "visibleEventsOnly"
],
v86 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v42/*: any*/)
],
v87 = [
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
v88 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v45/*: any*/),
    (v44/*: any*/)
  ],
  "storageKey": null
},
v89 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v90 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v91 = {
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
                (v47/*: any*/),
                (v9/*: any*/),
                {
                  "alias": null,
                  "args": (v89/*: any*/),
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
                            (v90/*: any*/),
                            (v7/*: any*/),
                            (v61/*: any*/),
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
                    (v30/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v31/*: any*/),
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
              "args": (v89/*: any*/),
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
                    (v90/*: any*/),
                    (v7/*: any*/),
                    (v61/*: any*/),
                    (v18/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v30/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v2/*: any*/)
          ],
          "storageKey": null
        },
        (v83/*: any*/)
      ],
      "storageKey": null
    },
    (v88/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v92 = {
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
v93 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Node"
},
v94 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v95 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v96 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v97 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
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
  "type": "URI"
},
v100 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v101 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v102 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v103 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v104 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
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
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v126 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v127 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v128 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v129 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v130 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v131 = {
  "enumValues": (v130/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
},
v132 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v133 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v134 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v135 = {
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
v136 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
},
v137 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
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
  "enumValues": (v130/*: any*/),
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
                      (v2/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v3/*: any*/),
                          (v8/*: any*/),
                          (v7/*: any*/),
                          (v26/*: any*/),
                          (v27/*: any*/),
                          (v29/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      (v30/*: any*/)
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
                  (v31/*: any*/),
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
              (v32/*: any*/),
              (v33/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v34/*: any*/),
                  (v8/*: any*/),
                  (v3/*: any*/),
                  (v35/*: any*/),
                  (v36/*: any*/)
                ],
                "storageKey": null
              },
              (v37/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v38/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v39/*: any*/),
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
              (v40/*: any*/),
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
                      (v2/*: any*/),
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
                              (v2/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v3/*: any*/),
                                  (v7/*: any*/),
                                  (v41/*: any*/)
                                ],
                                "type": "IssueFieldText",
                                "abstractKey": null
                              },
                              (v30/*: any*/)
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
                              (v2/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v7/*: any*/),
                                  (v41/*: any*/)
                                ],
                                "type": "IssueFieldSingleSelect",
                                "abstractKey": null
                              },
                              (v30/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v7/*: any*/),
                          (v18/*: any*/),
                          (v19/*: any*/)
                        ],
                        "type": "IssueFieldSingleSelectValue",
                        "abstractKey": null
                      },
                      (v30/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "issueFieldValues(first:25)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v43/*: any*/),
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
                      (v44/*: any*/),
                      (v45/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v14/*: any*/),
                  (v84/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v43/*: any*/),
                "filters": (v85/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v86/*: any*/),
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
                  (v84/*: any*/)
                ],
                "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v86/*: any*/),
                "filters": (v85/*: any*/),
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
                    "args": (v87/*: any*/),
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
                              (v61/*: any*/),
                              (v19/*: any*/),
                              (v9/*: any*/),
                              (v2/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v83/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v88/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v87/*: any*/),
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
                  (v46/*: any*/)
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v51/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v48/*: any*/),
                  (v49/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v91/*: any*/),
                      (v92/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v91/*: any*/),
                      (v92/*: any*/),
                      (v47/*: any*/)
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
              (v27/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  (v7/*: any*/),
                  (v26/*: any*/),
                  (v29/*: any*/)
                ],
                "type": "Actor",
                "abstractKey": "__isActor"
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
    "id": "40636c53042501c9712d6410524aa9be",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": (v93/*: any*/),
        "issue.__isComment": (v94/*: any*/),
        "issue.__isIssueOrPullRequest": (v94/*: any*/),
        "issue.__isLabelable": (v94/*: any*/),
        "issue.__isNode": (v94/*: any*/),
        "issue.__isReactable": (v94/*: any*/),
        "issue.__typename": (v94/*: any*/),
        "issue.assignedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "issue.assignedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "issue.assignedActors.nodes.__isActor": (v94/*: any*/),
        "issue.assignedActors.nodes.__isNode": (v94/*: any*/),
        "issue.assignedActors.nodes.__typename": (v94/*: any*/),
        "issue.assignedActors.nodes.avatarUrl": (v95/*: any*/),
        "issue.assignedActors.nodes.id": (v96/*: any*/),
        "issue.assignedActors.nodes.isCopilot": (v97/*: any*/),
        "issue.assignedActors.nodes.login": (v94/*: any*/),
        "issue.assignedActors.nodes.name": (v98/*: any*/),
        "issue.assignedActors.nodes.profileResourcePath": (v99/*: any*/),
        "issue.author": (v100/*: any*/),
        "issue.author.__isActor": (v94/*: any*/),
        "issue.author.__typename": (v94/*: any*/),
        "issue.author.avatarUrl": (v95/*: any*/),
        "issue.author.id": (v96/*: any*/),
        "issue.author.login": (v94/*: any*/),
        "issue.author.profileUrl": (v99/*: any*/),
        "issue.backTimelineItems": (v101/*: any*/),
        "issue.backTimelineItems.edges": (v102/*: any*/),
        "issue.backTimelineItems.edges.cursor": (v94/*: any*/),
        "issue.backTimelineItems.edges.node": (v103/*: any*/),
        "issue.backTimelineItems.edges.node.__id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.__isComment": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.__isIssueTimelineItems": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.__isReactable": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.__isTimelineEvent": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.actor": (v100/*: any*/),
        "issue.backTimelineItems.edges.node.actor.__isActor": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.actor.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.actor.avatarUrl": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.actor.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.actor.isCopilot": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.actor.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.actor.profileResourcePath": (v99/*: any*/),
        "issue.backTimelineItems.edges.node.assignee": (v104/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.__isActor": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.isCopilot": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.assignee.resourcePath": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.author": (v100/*: any*/),
        "issue.backTimelineItems.edges.node.author.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.author.avatarUrl": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.author.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.author.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.author.profileUrl": (v99/*: any*/),
        "issue.backTimelineItems.edges.node.authorAssociation": (v105/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v106/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.blockDuration": (v108/*: any*/),
        "issue.backTimelineItems.edges.node.blockedUser": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.blockedUser.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.blockedUser.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.body": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.bodyHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.bodyVersion": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.__isReferencedSubject": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.isDraft": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.isInMergeQueue": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.issueTitleHTML": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.pullTitleHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.isPrivate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.state": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.stateReason": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.canonical.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.closer": (v117/*: any*/),
        "issue.backTimelineItems.edges.node.closer.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.abbreviatedOid": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.closer.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.closer.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.title": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.closer.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.closingProjectItemStatus": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit": (v118/*: any*/),
        "issue.backTimelineItems.edges.node.commit.abbreviatedOid": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.hasSignature": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.commit.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.commit.message": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.messageBodyHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.commit.messageHeadlineHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.defaultBranch": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.commit.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature": (v119/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.commonName": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.organization": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.keyFingerprint": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.keyId": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer": (v109/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.signer.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.state": (v121/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject": (v120/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.commonName": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.emailAddress": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.organization": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.commit.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.commit.verificationStatus": (v122/*: any*/),
        "issue.backTimelineItems.edges.node.createdAt": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.createdViaEmail": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.currentTitle": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.databaseId": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor": (v100/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.deletedCommentAuthor.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.discussion": (v124/*: any*/),
        "issue.backTimelineItems.edges.node.discussion.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.discussion.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.discussion.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf": (v111/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.isDraft": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.state": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.stateReason": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.duplicateOf.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository": (v125/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository.nameWithOwner": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.fromRepository.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource": (v126/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.__isReferencedSubject": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.isDraft": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.isInMergeQueue": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.issueTitleHTML": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.pullTitleHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.isPrivate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.state": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.stateReason": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.innerSource.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v127/*: any*/),
        "issue.backTimelineItems.edges.node.isHidden": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.issue": (v128/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author": (v100/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.issue.author.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.issue.databaseId": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.issue.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.issue.locked": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.issue.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.issueType": (v129/*: any*/),
        "issue.backTimelineItems.edges.node.issueType.color": (v131/*: any*/),
        "issue.backTimelineItems.edges.node.issueType.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.issueType.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.label": (v132/*: any*/),
        "issue.backTimelineItems.edges.node.label.color": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.label.description": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.label.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.label.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.label.nameHTML": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.lastEditedAt": (v133/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit": (v134/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor": (v100/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.editor.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.lastUserContentEdit.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.lockReason": (v135/*: any*/),
        "issue.backTimelineItems.edges.node.milestone": (v136/*: any*/),
        "issue.backTimelineItems.edges.node.milestone.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.milestone.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.milestoneTitle": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.minimizedReason": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.parent": (v137/*: any*/),
        "issue.backTimelineItems.edges.node.parent.__isReferencedSubject": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.databaseId": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.parent.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.parent.isDraft": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.parent.isInMergeQueue": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.parent.issueTitleHTML": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.parent.pullTitleHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.isPrivate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.parent.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.parent.state": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.parent.stateReason": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.parent.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.pendingBlock": (v127/*: any*/),
        "issue.backTimelineItems.edges.node.pendingMinimizeReason": (v98/*: any*/),
        "issue.backTimelineItems.edges.node.pendingUnblock": (v127/*: any*/),
        "issue.backTimelineItems.edges.node.pendingUndo": (v127/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType": (v129/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType.color": (v131/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.prevIssueType.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.previousStatus": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.previousTitle": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.project": (v138/*: any*/),
        "issue.backTimelineItems.edges.node.project.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.project.title": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.project.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups": (v139/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.content": (v140/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.isCopilot": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.referencedAt": (v107/*: any*/),
        "issue.backTimelineItems.edges.node.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.repository.databaseId": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.repository.isPrivate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.repository.nameWithOwner": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.repository.owner.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.repository.slashCommandsEnabled": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.showSpammyBadge": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.source": (v126/*: any*/),
        "issue.backTimelineItems.edges.node.source.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.source.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.source.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.stateReason": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.status": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue": (v137/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.__isReferencedSubject": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.databaseId": (v123/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.isDraft": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.isInMergeQueue": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.issueTitleHTML": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.pullTitleHTML": (v110/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.isPrivate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.state": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.stateReason": (v116/*: any*/),
        "issue.backTimelineItems.edges.node.subIssue.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.subject": (v126/*: any*/),
        "issue.backTimelineItems.edges.node.subject.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.subject.isDraft": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.subject.isInMergeQueue": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.subject.number": (v112/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.name": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner": (v114/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.subject.repository.owner.login": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.state": (v115/*: any*/),
        "issue.backTimelineItems.edges.node.subject.title": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.subject.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.target": (v126/*: any*/),
        "issue.backTimelineItems.edges.node.target.__isNode": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.target.__typename": (v94/*: any*/),
        "issue.backTimelineItems.edges.node.target.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.target.repository": (v113/*: any*/),
        "issue.backTimelineItems.edges.node.target.repository.id": (v96/*: any*/),
        "issue.backTimelineItems.edges.node.url": (v95/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanBlockFromOrg": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanDelete": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanMinimize": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanReadUserContentEdits": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanReport": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanReportToMaintainer": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanUnblockFromOrg": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanUndo": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerCanUpdate": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.viewerDidAuthor": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.willCloseSubject": (v97/*: any*/),
        "issue.backTimelineItems.edges.node.willCloseTarget": (v97/*: any*/),
        "issue.backTimelineItems.pageInfo": (v143/*: any*/),
        "issue.backTimelineItems.pageInfo.hasPreviousPage": (v97/*: any*/),
        "issue.backTimelineItems.pageInfo.startCursor": (v98/*: any*/),
        "issue.backTimelineItems.totalCount": (v112/*: any*/),
        "issue.body": (v94/*: any*/),
        "issue.bodyHTML": (v110/*: any*/),
        "issue.bodyVersion": (v94/*: any*/),
        "issue.createdAt": (v107/*: any*/),
        "issue.databaseId": (v123/*: any*/),
        "issue.duplicateOf": (v137/*: any*/),
        "issue.duplicateOf.id": (v96/*: any*/),
        "issue.duplicateOf.number": (v112/*: any*/),
        "issue.duplicateOf.repository": (v113/*: any*/),
        "issue.duplicateOf.repository.id": (v96/*: any*/),
        "issue.duplicateOf.repository.name": (v94/*: any*/),
        "issue.duplicateOf.repository.owner": (v114/*: any*/),
        "issue.duplicateOf.repository.owner.__typename": (v94/*: any*/),
        "issue.duplicateOf.repository.owner.id": (v96/*: any*/),
        "issue.duplicateOf.repository.owner.login": (v94/*: any*/),
        "issue.duplicateOf.url": (v95/*: any*/),
        "issue.frontTimelineItems": (v101/*: any*/),
        "issue.frontTimelineItems.edges": (v102/*: any*/),
        "issue.frontTimelineItems.edges.cursor": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node": (v103/*: any*/),
        "issue.frontTimelineItems.edges.node.__id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.__isComment": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.__isIssueTimelineItems": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.__isReactable": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.__isTimelineEvent": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.actor": (v100/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.__isActor": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.avatarUrl": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.isCopilot": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.actor.profileResourcePath": (v99/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee": (v104/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.__isActor": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.isCopilot": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.assignee.resourcePath": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.author": (v100/*: any*/),
        "issue.frontTimelineItems.edges.node.author.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.author.avatarUrl": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.author.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.author.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.author.profileUrl": (v99/*: any*/),
        "issue.frontTimelineItems.edges.node.authorAssociation": (v105/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v106/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.blockDuration": (v108/*: any*/),
        "issue.frontTimelineItems.edges.node.blockedUser": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.blockedUser.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.blockedUser.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.body": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.bodyHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.bodyVersion": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.__isReferencedSubject": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.isDraft": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.isInMergeQueue": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.issueTitleHTML": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.pullTitleHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.isPrivate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.state": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.stateReason": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.canonical.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.closer": (v117/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.abbreviatedOid": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.title": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.closer.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.closingProjectItemStatus": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit": (v118/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.abbreviatedOid": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.hasSignature": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.message": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.messageBodyHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.messageHeadlineHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.defaultBranch": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature": (v119/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.commonName": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.organization": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.keyFingerprint": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.keyId": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer": (v109/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.signer.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.state": (v121/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject": (v120/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.commonName": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.emailAddress": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.organization": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.commit.verificationStatus": (v122/*: any*/),
        "issue.frontTimelineItems.edges.node.createdAt": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.createdViaEmail": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.currentTitle": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.databaseId": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor": (v100/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.deletedCommentAuthor.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion": (v124/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.discussion.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf": (v111/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.isDraft": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.state": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.stateReason": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.duplicateOf.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository": (v125/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository.nameWithOwner": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.fromRepository.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource": (v126/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.__isReferencedSubject": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.isDraft": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.isInMergeQueue": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.issueTitleHTML": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.pullTitleHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.isPrivate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.state": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.stateReason": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.innerSource.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v127/*: any*/),
        "issue.frontTimelineItems.edges.node.isHidden": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.issue": (v128/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author": (v100/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.author.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.databaseId": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.locked": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.issue.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType": (v129/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType.color": (v131/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.issueType.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.label": (v132/*: any*/),
        "issue.frontTimelineItems.edges.node.label.color": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.label.description": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.label.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.label.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.label.nameHTML": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.lastEditedAt": (v133/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit": (v134/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor": (v100/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.lastUserContentEdit.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.lockReason": (v135/*: any*/),
        "issue.frontTimelineItems.edges.node.milestone": (v136/*: any*/),
        "issue.frontTimelineItems.edges.node.milestone.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.milestone.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.milestoneTitle": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.minimizedReason": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.parent": (v137/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.__isReferencedSubject": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.databaseId": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.isDraft": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.isInMergeQueue": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.issueTitleHTML": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.pullTitleHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.isPrivate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.state": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.stateReason": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.parent.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingBlock": (v127/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingMinimizeReason": (v98/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingUnblock": (v127/*: any*/),
        "issue.frontTimelineItems.edges.node.pendingUndo": (v127/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType": (v129/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType.color": (v131/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.prevIssueType.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.previousStatus": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.previousTitle": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.project": (v138/*: any*/),
        "issue.frontTimelineItems.edges.node.project.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.project.title": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.project.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups": (v139/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.content": (v140/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors": (v141/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes": (v142/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.isCopilot": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.referencedAt": (v107/*: any*/),
        "issue.frontTimelineItems.edges.node.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.databaseId": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.isPrivate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.nameWithOwner": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.owner.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.repository.slashCommandsEnabled": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.showSpammyBadge": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.source": (v126/*: any*/),
        "issue.frontTimelineItems.edges.node.source.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.source.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.source.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.stateReason": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.status": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue": (v137/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.__isReferencedSubject": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.databaseId": (v123/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.isDraft": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.isInMergeQueue": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.issueTitleHTML": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.pullTitleHTML": (v110/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.isPrivate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.state": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.stateReason": (v116/*: any*/),
        "issue.frontTimelineItems.edges.node.subIssue.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.subject": (v126/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.isDraft": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.isInMergeQueue": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.number": (v112/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.name": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner": (v114/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.repository.owner.login": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.state": (v115/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.title": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.subject.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.target": (v126/*: any*/),
        "issue.frontTimelineItems.edges.node.target.__isNode": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.target.__typename": (v94/*: any*/),
        "issue.frontTimelineItems.edges.node.target.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.target.repository": (v113/*: any*/),
        "issue.frontTimelineItems.edges.node.target.repository.id": (v96/*: any*/),
        "issue.frontTimelineItems.edges.node.url": (v95/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanBlockFromOrg": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanDelete": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanMinimize": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanReadUserContentEdits": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanReport": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanReportToMaintainer": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanUnblockFromOrg": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanUndo": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerCanUpdate": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.viewerDidAuthor": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.willCloseSubject": (v97/*: any*/),
        "issue.frontTimelineItems.edges.node.willCloseTarget": (v97/*: any*/),
        "issue.frontTimelineItems.pageInfo": (v143/*: any*/),
        "issue.frontTimelineItems.pageInfo.endCursor": (v98/*: any*/),
        "issue.frontTimelineItems.pageInfo.hasNextPage": (v97/*: any*/),
        "issue.frontTimelineItems.totalCount": (v112/*: any*/),
        "issue.id": (v96/*: any*/),
        "issue.isPinned": (v127/*: any*/),
        "issue.issueFieldValues": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFieldValueConnection"
        },
        "issue.issueFieldValues.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueFieldValue"
        },
        "issue.issueFieldValues.nodes.__isNode": (v94/*: any*/),
        "issue.issueFieldValues.nodes.__typename": (v94/*: any*/),
        "issue.issueFieldValues.nodes.color": {
          "enumValues": (v130/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueFieldSingleSelectOptionColor"
        },
        "issue.issueFieldValues.nodes.description": (v98/*: any*/),
        "issue.issueFieldValues.nodes.field": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFields"
        },
        "issue.issueFieldValues.nodes.field.__isNode": (v94/*: any*/),
        "issue.issueFieldValues.nodes.field.__typename": (v94/*: any*/),
        "issue.issueFieldValues.nodes.field.dataType": {
          "enumValues": [
            "SINGLE_SELECT",
            "TEXT"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueFieldDataType"
        },
        "issue.issueFieldValues.nodes.field.id": (v96/*: any*/),
        "issue.issueFieldValues.nodes.field.name": (v94/*: any*/),
        "issue.issueFieldValues.nodes.id": (v96/*: any*/),
        "issue.issueFieldValues.nodes.name": (v94/*: any*/),
        "issue.issueFieldValues.nodes.value": (v94/*: any*/),
        "issue.issueType": (v129/*: any*/),
        "issue.issueType.color": (v131/*: any*/),
        "issue.issueType.description": (v98/*: any*/),
        "issue.issueType.id": (v96/*: any*/),
        "issue.issueType.isEnabled": (v97/*: any*/),
        "issue.issueType.name": (v94/*: any*/),
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
        "issue.labels.edges.cursor": (v94/*: any*/),
        "issue.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "issue.labels.edges.node.__typename": (v94/*: any*/),
        "issue.labels.edges.node.color": (v94/*: any*/),
        "issue.labels.edges.node.description": (v98/*: any*/),
        "issue.labels.edges.node.id": (v96/*: any*/),
        "issue.labels.edges.node.name": (v94/*: any*/),
        "issue.labels.edges.node.nameHTML": (v94/*: any*/),
        "issue.labels.edges.node.url": (v95/*: any*/),
        "issue.labels.pageInfo": (v143/*: any*/),
        "issue.labels.pageInfo.endCursor": (v98/*: any*/),
        "issue.labels.pageInfo.hasNextPage": (v97/*: any*/),
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
        "issue.linkedPullRequests.nodes.id": (v96/*: any*/),
        "issue.linkedPullRequests.nodes.isDraft": (v97/*: any*/),
        "issue.linkedPullRequests.nodes.number": (v112/*: any*/),
        "issue.linkedPullRequests.nodes.repository": (v113/*: any*/),
        "issue.linkedPullRequests.nodes.repository.id": (v96/*: any*/),
        "issue.linkedPullRequests.nodes.repository.name": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.repository.nameWithOwner": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner": (v114/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.__typename": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.id": (v96/*: any*/),
        "issue.linkedPullRequests.nodes.repository.owner.login": (v94/*: any*/),
        "issue.linkedPullRequests.nodes.state": (v115/*: any*/),
        "issue.linkedPullRequests.nodes.url": (v95/*: any*/),
        "issue.locked": (v97/*: any*/),
        "issue.milestone": (v136/*: any*/),
        "issue.milestone.closed": (v97/*: any*/),
        "issue.milestone.closedAt": (v133/*: any*/),
        "issue.milestone.dueOn": (v133/*: any*/),
        "issue.milestone.id": (v96/*: any*/),
        "issue.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "issue.milestone.title": (v94/*: any*/),
        "issue.milestone.url": (v95/*: any*/),
        "issue.number": (v112/*: any*/),
        "issue.pendingBlock": (v127/*: any*/),
        "issue.pendingUnblock": (v127/*: any*/),
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
        "issue.projectItemsNext.edges.cursor": (v94/*: any*/),
        "issue.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "issue.projectItemsNext.edges.node.__typename": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "issue.projectItemsNext.edges.node.fieldValueByName.__isNode": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.__typename": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.color": (v144/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.id": (v96/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.name": (v98/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v98/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.optionId": (v98/*: any*/),
        "issue.projectItemsNext.edges.node.id": (v96/*: any*/),
        "issue.projectItemsNext.edges.node.isArchived": (v97/*: any*/),
        "issue.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "issue.projectItemsNext.edges.node.project.__typename": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.closed": (v97/*: any*/),
        "issue.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "issue.projectItemsNext.edges.node.project.field.__isNode": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.__typename": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.id": (v96/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.name": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "issue.projectItemsNext.edges.node.project.field.options.color": (v144/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.description": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.id": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.name": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.nameHTML": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.optionId": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v97/*: any*/),
        "issue.projectItemsNext.edges.node.project.id": (v96/*: any*/),
        "issue.projectItemsNext.edges.node.project.number": (v112/*: any*/),
        "issue.projectItemsNext.edges.node.project.template": (v97/*: any*/),
        "issue.projectItemsNext.edges.node.project.title": (v94/*: any*/),
        "issue.projectItemsNext.edges.node.project.url": (v95/*: any*/),
        "issue.projectItemsNext.edges.node.project.viewerCanUpdate": (v97/*: any*/),
        "issue.projectItemsNext.pageInfo": (v143/*: any*/),
        "issue.projectItemsNext.pageInfo.endCursor": (v98/*: any*/),
        "issue.projectItemsNext.pageInfo.hasNextPage": (v97/*: any*/),
        "issue.reactionGroups": (v139/*: any*/),
        "issue.reactionGroups.content": (v140/*: any*/),
        "issue.reactionGroups.reactors": (v141/*: any*/),
        "issue.reactionGroups.reactors.nodes": (v142/*: any*/),
        "issue.reactionGroups.reactors.nodes.__isNode": (v94/*: any*/),
        "issue.reactionGroups.reactors.nodes.__typename": (v94/*: any*/),
        "issue.reactionGroups.reactors.nodes.id": (v96/*: any*/),
        "issue.reactionGroups.reactors.nodes.isCopilot": (v97/*: any*/),
        "issue.reactionGroups.reactors.nodes.login": (v94/*: any*/),
        "issue.reactionGroups.reactors.totalCount": (v112/*: any*/),
        "issue.reactionGroups.viewerHasReacted": (v97/*: any*/),
        "issue.repository": (v113/*: any*/),
        "issue.repository.databaseId": (v123/*: any*/),
        "issue.repository.id": (v96/*: any*/),
        "issue.repository.isArchived": (v97/*: any*/),
        "issue.repository.isPrivate": (v97/*: any*/),
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
        "issue.repository.issueTypes.edges.node": (v129/*: any*/),
        "issue.repository.issueTypes.edges.node.id": (v96/*: any*/),
        "issue.repository.name": (v94/*: any*/),
        "issue.repository.nameWithOwner": (v94/*: any*/),
        "issue.repository.owner": (v114/*: any*/),
        "issue.repository.owner.__typename": (v94/*: any*/),
        "issue.repository.owner.id": (v96/*: any*/),
        "issue.repository.owner.login": (v94/*: any*/),
        "issue.repository.owner.url": (v95/*: any*/),
        "issue.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "issue.repository.pinnedIssues.totalCount": (v112/*: any*/),
        "issue.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "issue.repository.planFeatures.maximumAssignees": (v112/*: any*/),
        "issue.repository.slashCommandsEnabled": (v97/*: any*/),
        "issue.repository.viewerCanInteract": (v97/*: any*/),
        "issue.repository.viewerCanPinIssues": (v97/*: any*/),
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
        "issue.stateReason": (v116/*: any*/),
        "issue.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "issue.subIssuesSummary.completed": (v112/*: any*/),
        "issue.subIssuesSummary.total": (v112/*: any*/),
        "issue.title": (v94/*: any*/),
        "issue.titleHTML": (v94/*: any*/),
        "issue.updatedAt": (v107/*: any*/),
        "issue.url": (v95/*: any*/),
        "issue.viewerCanAssign": (v97/*: any*/),
        "issue.viewerCanComment": (v97/*: any*/),
        "issue.viewerCanConvertToDiscussion": (v127/*: any*/),
        "issue.viewerCanDelete": (v97/*: any*/),
        "issue.viewerCanLabel": (v97/*: any*/),
        "issue.viewerCanLock": (v127/*: any*/),
        "issue.viewerCanSetMilestone": (v97/*: any*/),
        "issue.viewerCanTransfer": (v97/*: any*/),
        "issue.viewerCanType": (v127/*: any*/),
        "issue.viewerCanUpdate": (v97/*: any*/),
        "issue.viewerCanUpdateMetadata": (v127/*: any*/),
        "issue.viewerCanUpdateNext": (v127/*: any*/),
        "issue.viewerDidAuthor": (v97/*: any*/),
        "viewer": (v93/*: any*/),
        "viewer.__isActor": (v94/*: any*/),
        "viewer.__typename": (v94/*: any*/),
        "viewer.avatarUrl": (v95/*: any*/),
        "viewer.enterpriseManagedEnterpriseId": (v98/*: any*/),
        "viewer.id": (v96/*: any*/),
        "viewer.isCopilot": (v97/*: any*/),
        "viewer.isEnterpriseManagedUser": (v127/*: any*/),
        "viewer.login": (v94/*: any*/),
        "viewer.name": (v98/*: any*/),
        "viewer.profileResourcePath": (v99/*: any*/)
      }
    },
    "name": "IssueViewerTestComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "624fe1f9d67bd96dbd4c48ed79168a42";

export default node;
