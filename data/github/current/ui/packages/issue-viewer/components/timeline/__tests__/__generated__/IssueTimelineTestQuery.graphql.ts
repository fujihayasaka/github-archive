/**
 * @generated SignedSource<<02d280c2f26323af61d84310becfaf01>>
 * @relayHash 8896a9347263ff05d33f06c5a510dd6c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 8896a9347263ff05d33f06c5a510dd6c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTimelineTestQuery$variables = Record<PropertyKey, never>;
export type IssueTimelineTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineIssueFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type IssueTimelineTestQuery = {
  response: IssueTimelineTestQuery$data;
  variables: IssueTimelineTestQuery$variables;
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
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 33
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v5 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v6 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
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
  "name": "__typename",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v12 = [
  (v8/*: any*/),
  (v11/*: any*/),
  (v2/*: any*/)
],
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v17 = [
  (v11/*: any*/)
],
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCopilot",
  "storageKey": null
},
v19 = [
  (v2/*: any*/)
],
v20 = {
  "kind": "InlineFragment",
  "selections": (v19/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v21 = [
  (v8/*: any*/),
  (v20/*: any*/)
],
v22 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v19/*: any*/),
  "storageKey": null
},
v23 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v24 = {
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
v25 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v12/*: any*/),
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v15/*: any*/),
    (v16/*: any*/),
    (v25/*: any*/)
  ],
  "storageKey": null
},
v27 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v23/*: any*/),
    (v3/*: any*/),
    (v13/*: any*/),
    (v24/*: any*/),
    (v26/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v28 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v32 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v28/*: any*/),
    (v3/*: any*/),
    (v13/*: any*/),
    (v29/*: any*/),
    (v30/*: any*/),
    (v31/*: any*/),
    (v26/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v33 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v34 = {
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
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v36 = {
  "kind": "InlineFragment",
  "selections": [
    (v18/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v33/*: any*/),
    (v34/*: any*/),
    (v11/*: any*/),
    (v35/*: any*/),
    (v36/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v39 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v2/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v15/*: any*/),
      (v38/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "description",
        "storageKey": null
      }
    ],
    "storageKey": null
  },
  (v9/*: any*/),
  (v10/*: any*/),
  (v37/*: any*/)
],
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v41 = [
  (v11/*: any*/),
  (v40/*: any*/)
],
v42 = {
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
      "selections": (v19/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v19/*: any*/),
      "type": "Bot",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v19/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v19/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    (v20/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": [
        (v11/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v41/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v41/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v41/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v40/*: any*/),
            (v18/*: any*/)
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
v43 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v2/*: any*/),
      (v3/*: any*/)
    ],
    "storageKey": null
  },
  (v9/*: any*/),
  (v10/*: any*/),
  (v37/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v44 = [
  (v10/*: any*/),
  (v9/*: any*/),
  (v37/*: any*/)
],
v45 = {
  "kind": "InlineFragment",
  "selections": [
    (v27/*: any*/),
    (v32/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v47 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    (v25/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v49 = [
  (v9/*: any*/),
  (v10/*: any*/),
  (v37/*: any*/)
],
v50 = [
  (v9/*: any*/),
  (v37/*: any*/),
  (v10/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v9/*: any*/),
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v8/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v23/*: any*/),
              (v3/*: any*/),
              (v13/*: any*/),
              (v24/*: any*/),
              (v26/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v28/*: any*/),
              (v3/*: any*/),
              (v13/*: any*/),
              (v29/*: any*/),
              (v30/*: any*/),
              (v31/*: any*/),
              (v26/*: any*/)
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
v51 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    (v16/*: any*/),
    (v25/*: any*/)
  ],
  "storageKey": null
},
v52 = [
  (v9/*: any*/),
  (v37/*: any*/),
  (v10/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v22/*: any*/),
      (v9/*: any*/),
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v8/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v23/*: any*/),
              (v3/*: any*/),
              (v13/*: any*/),
              (v24/*: any*/),
              (v51/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v28/*: any*/),
              (v3/*: any*/),
              (v13/*: any*/),
              (v29/*: any*/),
              (v30/*: any*/),
              (v31/*: any*/),
              (v51/*: any*/)
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
v53 = [
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
v54 = [
  (v9/*: any*/),
  (v37/*: any*/),
  (v10/*: any*/),
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
          (v46/*: any*/),
          (v3/*: any*/),
          (v13/*: any*/),
          (v29/*: any*/),
          (v30/*: any*/),
          (v31/*: any*/),
          (v47/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v20/*: any*/)
    ],
    "storageKey": null
  }
],
v55 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v23/*: any*/),
        (v3/*: any*/),
        (v24/*: any*/),
        (v26/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v28/*: any*/),
        (v3/*: any*/),
        (v29/*: any*/),
        (v30/*: any*/),
        (v31/*: any*/),
        (v26/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v56 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v57 = [
  (v45/*: any*/)
],
v58 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v46/*: any*/),
    (v3/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v59 = [
  (v15/*: any*/),
  (v38/*: any*/),
  (v2/*: any*/)
],
v60 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v59/*: any*/),
  "storageKey": null
},
v61 = [
  (v9/*: any*/),
  (v37/*: any*/),
  (v10/*: any*/),
  (v60/*: any*/)
],
v62 = {
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
            (v9/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": (v12/*: any*/),
              "storageKey": null
            }
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerDidAuthor",
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
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "author",
                  "plural": false,
                  "selections": (v12/*: any*/),
                  "storageKey": null
                },
                (v2/*: any*/),
                (v13/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "locked",
                  "storageKey": null
                },
                (v9/*: any*/)
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
                (v11/*: any*/),
                (v14/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "profileUrl",
                  "storageKey": null
                },
                (v2/*: any*/)
              ],
              "storageKey": null
            },
            (v2/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "body",
              "storageKey": null
            },
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
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanUpdate",
              "storageKey": null
            },
            (v3/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "authorAssociation",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanDelete",
              "storageKey": null
            },
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
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "isActive",
                  "storageKey": null
                },
                (v2/*: any*/)
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
                (v2/*: any*/),
                (v15/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "owner",
                  "plural": false,
                  "selections": [
                    (v8/*: any*/),
                    (v2/*: any*/),
                    (v11/*: any*/),
                    (v3/*: any*/)
                  ],
                  "storageKey": null
                },
                (v16/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "slashCommandsEnabled",
                  "storageKey": null
                },
                (v4/*: any*/),
                (v9/*: any*/)
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
                        (v3/*: any*/),
                        (v11/*: any*/),
                        (v2/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v2/*: any*/)
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
            {
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
                            (v8/*: any*/),
                            {
                              "kind": "InlineFragment",
                              "selections": (v17/*: any*/),
                              "type": "User",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": [
                                (v11/*: any*/),
                                (v18/*: any*/)
                              ],
                              "type": "Bot",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": (v17/*: any*/),
                              "type": "Organization",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": (v17/*: any*/),
                              "type": "Mannequin",
                              "abstractKey": null
                            },
                            (v20/*: any*/)
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
            }
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
              "selections": (v21/*: any*/),
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
            (v9/*: any*/),
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
                    (v22/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v20/*: any*/)
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
                (v27/*: any*/),
                (v32/*: any*/),
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v37/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v39/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v39/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v9/*: any*/),
            (v10/*: any*/),
            (v37/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v9/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                (v11/*: any*/),
                (v33/*: any*/),
                (v34/*: any*/),
                (v35/*: any*/),
                (v36/*: any*/),
                (v2/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v43/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v43/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v44/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v44/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v44/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v10/*: any*/),
            (v24/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                (v45/*: any*/),
                (v20/*: any*/)
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
                    (v3/*: any*/),
                    (v46/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v13/*: any*/),
                    (v47/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v48/*: any*/),
                    (v47/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v37/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v49/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v37/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v49/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v49/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v49/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v10/*: any*/),
            (v37/*: any*/),
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
            (v9/*: any*/),
            (v10/*: any*/),
            (v37/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "deletedCommentAuthor",
              "plural": false,
              "selections": (v12/*: any*/),
              "storageKey": null
            }
          ],
          "type": "CommentDeletedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v37/*: any*/),
            {
              "alias": "blockedUser",
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": [
                (v11/*: any*/),
                (v2/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UserBlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v50/*: any*/),
          "type": "SubIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v50/*: any*/),
          "type": "SubIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v52/*: any*/),
          "type": "ParentIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v52/*: any*/),
          "type": "ParentIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
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
              "selections": (v21/*: any*/),
              "storageKey": null
            },
            (v37/*: any*/),
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
                (v3/*: any*/),
                (v48/*: any*/),
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
                        (v11/*: any*/),
                        (v14/*: any*/),
                        (v2/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v29/*: any*/),
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
                          "selections": (v53/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v53/*: any*/),
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
                    (v15/*: any*/),
                    (v25/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "defaultBranch",
                      "storageKey": null
                    },
                    (v2/*: any*/)
                  ],
                  "storageKey": null
                },
                (v2/*: any*/)
              ],
              "storageKey": null
            },
            (v10/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v54/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v37/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v4/*: any*/),
                (v3/*: any*/),
                (v2/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "TransferredEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v54/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v37/*: any*/),
            (v10/*: any*/),
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
                    (v2/*: any*/),
                    (v13/*: any*/),
                    (v55/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v13/*: any*/),
                    (v2/*: any*/),
                    (v55/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v56/*: any*/),
            (v9/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanUndo",
              "storageKey": null
            },
            (v2/*: any*/),
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
            (v37/*: any*/),
            (v10/*: any*/),
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
                  "selections": (v57/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v57/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v56/*: any*/),
            (v9/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v37/*: any*/),
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v3/*: any*/),
                (v13/*: any*/),
                (v2/*: any*/)
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
            (v9/*: any*/),
            (v10/*: any*/),
            (v37/*: any*/),
            (v58/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v37/*: any*/),
            (v58/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v37/*: any*/),
            (v58/*: any*/),
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
            (v10/*: any*/),
            (v37/*: any*/),
            (v9/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v61/*: any*/),
          "type": "IssueTypeAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v61/*: any*/),
          "type": "IssueTypeRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v37/*: any*/),
            (v10/*: any*/),
            (v60/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "prevIssueType",
              "plural": false,
              "selections": (v59/*: any*/),
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
        (v20/*: any*/)
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
v63 = [
  "visibleEventsOnly"
],
v64 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v5/*: any*/)
],
v65 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v66 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v67 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v68 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v69 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v70 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v71 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v72 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v73 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v74 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v75 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v76 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
},
v77 = {
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
v78 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Sponsorship"
},
v79 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v80 = {
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
v81 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v82 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v83 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v84 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v85 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v86 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v87 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v88 = {
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
v89 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v90 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v91 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v92 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitSignature"
},
v93 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v94 = {
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
v95 = {
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
v96 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v97 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Discussion"
},
v98 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v99 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v100 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v101 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v102 = {
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
  "type": "IssueTypeColor"
},
v103 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v104 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v105 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v106 = {
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
v107 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
},
v108 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "ProjectV2"
},
v109 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "ReactionGroup"
},
v110 = {
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
v111 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReactorConnection"
},
v112 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Reactor"
},
v113 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTimelineTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueTimelineIssueFragment"
              }
            ],
            "storageKey": "issue(number:33)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueTimelineTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v4/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "frontTimelineItems",
                "args": (v6/*: any*/),
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
                        "name": "hasNextPage",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "endCursor",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v7/*: any*/),
                  (v62/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v6/*: any*/),
                "filters": (v63/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v64/*: any*/),
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
                  (v7/*: any*/),
                  (v62/*: any*/)
                ],
                "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v64/*: any*/),
                "filters": (v63/*: any*/),
                "handle": "connection",
                "key": "Issue__backTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              }
            ],
            "storageKey": "issue(number:33)"
          },
          (v2/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "8896a9347263ff05d33f06c5a510dd6c",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": (v65/*: any*/),
        "repository.id": (v66/*: any*/),
        "repository.issue": (v67/*: any*/),
        "repository.issue.backTimelineItems": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges": (v69/*: any*/),
        "repository.issue.backTimelineItems.edges.cursor": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isComment": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isIssueTimelineItems": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isReactable": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isTimelineEvent": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__isActor": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.avatarUrl": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.isCopilot": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.profileResourcePath": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee": (v76/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__isActor": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.isCopilot": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.resourcePath": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.avatarUrl": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.profileUrl": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorAssociation": (v77/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v78/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockDuration": (v80/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser": (v81/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.body": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyVersion": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical": (v83/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isDraft": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isInMergeQueue": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.issueTitleHTML": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.pullTitleHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.isPrivate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.state": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.stateReason": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer": (v89/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.abbreviatedOid": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.title": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closingProjectItemStatus": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit": (v91/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.abbreviatedOid": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.hasSignature": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.message": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageBodyHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageHeadlineHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.defaultBranch": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature": (v92/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.commonName": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organization": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyFingerprint": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyId": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer": (v81/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.state": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.commonName": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.emailAddress": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organization": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.verificationStatus": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdAt": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdViaEmail": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.currentTitle": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.databaseId": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf": (v83/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isDraft": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.state": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.stateReason": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository": (v65/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.nameWithOwner": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isDraft": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isInMergeQueue": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.issueTitleHTML": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.pullTitleHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.isPrivate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.state": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.stateReason": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isHidden": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue": (v100/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.databaseId": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.locked": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.color": (v102/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issueType.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label": (v103/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.color": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.description": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.nameHTML": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastEditedAt": (v104/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit": (v105/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lockReason": (v106/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone": (v107/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestoneTitle": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.minimizedReason": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent": (v67/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.databaseId": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.isDraft": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.isInMergeQueue": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.issueTitleHTML": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.pullTitleHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.isPrivate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.state": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.stateReason": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.parent.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingBlock": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingMinimizeReason": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUnblock": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUndo": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType": (v101/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.color": (v102/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.prevIssueType.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousStatus": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousTitle": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project": (v108/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.title": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups": (v109/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.content": (v110/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors": (v111/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes": (v112/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.isCopilot": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.referencedAt": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.databaseId": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.isPrivate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.nameWithOwner": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.slashCommandsEnabled": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.showSpammyBadge": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.stateReason": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.status": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue": (v67/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.databaseId": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.isDraft": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.isInMergeQueue": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.issueTitleHTML": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.pullTitleHTML": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.isPrivate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.state": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.stateReason": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subIssue.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isDraft": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isInMergeQueue": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.number": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.name": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.login": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.state": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.title": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__isNode": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__typename": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository.id": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.url": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanBlockFromOrg": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanDelete": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanMinimize": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReadUserContentEdits": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReport": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReportToMaintainer": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUnblockFromOrg": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUndo": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUpdate": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerDidAuthor": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseSubject": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseTarget": (v74/*: any*/),
        "repository.issue.backTimelineItems.pageInfo": (v113/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.hasPreviousPage": (v74/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.startCursor": (v90/*: any*/),
        "repository.issue.backTimelineItems.totalCount": (v84/*: any*/),
        "repository.issue.frontTimelineItems": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges": (v69/*: any*/),
        "repository.issue.frontTimelineItems.edges.cursor": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isComment": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isIssueTimelineItems": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isReactable": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isTimelineEvent": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__isActor": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.avatarUrl": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.isCopilot": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.profileResourcePath": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee": (v76/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__isActor": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.isCopilot": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.resourcePath": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.avatarUrl": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.profileUrl": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorAssociation": (v77/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v78/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockDuration": (v80/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser": (v81/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.body": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyVersion": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical": (v83/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isDraft": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isInMergeQueue": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.issueTitleHTML": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.pullTitleHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.isPrivate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.state": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.stateReason": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer": (v89/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.abbreviatedOid": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.title": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closingProjectItemStatus": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit": (v91/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.abbreviatedOid": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.hasSignature": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.message": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageBodyHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageHeadlineHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.defaultBranch": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature": (v92/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.commonName": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organization": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyFingerprint": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyId": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer": (v81/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.state": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.commonName": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.emailAddress": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organization": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.verificationStatus": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdAt": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdViaEmail": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.currentTitle": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.databaseId": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf": (v83/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isDraft": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.state": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.stateReason": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository": (v65/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.nameWithOwner": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isDraft": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isInMergeQueue": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.issueTitleHTML": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.pullTitleHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.isPrivate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.state": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.stateReason": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isHidden": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue": (v100/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.databaseId": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.locked": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.color": (v102/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issueType.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label": (v103/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.color": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.description": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.nameHTML": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastEditedAt": (v104/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit": (v105/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lockReason": (v106/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone": (v107/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestoneTitle": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.minimizedReason": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent": (v67/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.databaseId": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.isDraft": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.isInMergeQueue": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.issueTitleHTML": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.pullTitleHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.isPrivate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.state": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.stateReason": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.parent.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingBlock": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingMinimizeReason": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUnblock": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUndo": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType": (v101/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.color": (v102/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.prevIssueType.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousStatus": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousTitle": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project": (v108/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.title": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups": (v109/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.content": (v110/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors": (v111/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes": (v112/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.isCopilot": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.referencedAt": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.databaseId": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.isPrivate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.nameWithOwner": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.slashCommandsEnabled": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.showSpammyBadge": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.stateReason": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.status": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue": (v67/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.__isReferencedSubject": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.databaseId": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.isDraft": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.isInMergeQueue": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.issueTitleHTML": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.pullTitleHTML": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.isPrivate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.state": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.stateReason": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subIssue.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isDraft": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isInMergeQueue": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.number": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.name": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.login": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.state": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.title": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__isNode": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__typename": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository.id": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.url": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanBlockFromOrg": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanDelete": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanMinimize": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReadUserContentEdits": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReport": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReportToMaintainer": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUnblockFromOrg": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUndo": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUpdate": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerDidAuthor": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseSubject": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseTarget": (v74/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo": (v113/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.endCursor": (v90/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.hasNextPage": (v74/*: any*/),
        "repository.issue.frontTimelineItems.totalCount": (v84/*: any*/),
        "repository.issue.id": (v66/*: any*/),
        "repository.issue.repository": (v85/*: any*/),
        "repository.issue.repository.id": (v66/*: any*/),
        "repository.issue.repository.nameWithOwner": (v70/*: any*/),
        "repository.issue.url": (v73/*: any*/)
      }
    },
    "name": "IssueTimelineTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "228e16defa8f1e45e6d68854fcc10094";

export default node;
