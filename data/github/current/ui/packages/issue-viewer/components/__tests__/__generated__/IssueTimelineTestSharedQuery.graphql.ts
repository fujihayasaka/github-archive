/**
 * @generated SignedSource<<bb5d221d6206ffe072becd2bcd37f0b5>>
 * @relayHash 3c05d19236e378ccbbfc359920c6d562
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3c05d19236e378ccbbfc359920c6d562

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueTimelineTestSharedQuery$variables = {
  number: number;
  owner: string;
  repo: string;
};
export type IssueTimelineTestSharedQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueTimelinePaginated">;
    } | null | undefined;
  } | null | undefined;
};
export type IssueTimelineTestSharedQuery = {
  response: IssueTimelineTestSharedQuery$data;
  variables: IssueTimelineTestSharedQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v3 = [
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
v4 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
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
  "name": "login",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = [
  (v5/*: any*/),
  (v6/*: any*/),
  (v7/*: any*/)
],
v9 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": (v8/*: any*/),
  "storageKey": null
},
v10 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v11 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 25
  },
  (v10/*: any*/)
],
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v14 = [
  (v7/*: any*/)
],
v15 = {
  "kind": "InlineFragment",
  "selections": (v14/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v16 = {
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
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v24 = [
  (v6/*: any*/)
],
v25 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
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
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v6/*: any*/),
    (v7/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/)
  ],
  "storageKey": null
},
v28 = [
  (v5/*: any*/),
  (v15/*: any*/)
],
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v31 = [
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
v32 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v8/*: any*/),
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v14/*: any*/),
  "storageKey": null
},
v34 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v35 = {
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
v36 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    (v21/*: any*/),
    (v22/*: any*/),
    (v32/*: any*/)
  ],
  "storageKey": null
},
v37 = {
  "kind": "InlineFragment",
  "selections": [
    (v7/*: any*/),
    (v34/*: any*/),
    (v18/*: any*/),
    (v17/*: any*/),
    (v35/*: any*/),
    (v36/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v38 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v41 = {
  "kind": "InlineFragment",
  "selections": [
    (v7/*: any*/),
    (v38/*: any*/),
    (v18/*: any*/),
    (v17/*: any*/),
    (v30/*: any*/),
    (v39/*: any*/),
    (v40/*: any*/),
    (v36/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v42 = [
  (v19/*: any*/),
  (v27/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v7/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v21/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "color",
        "storageKey": null
      },
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
  (v13/*: any*/)
],
v43 = [
  (v7/*: any*/),
  (v6/*: any*/)
],
v44 = [
  (v19/*: any*/),
  (v27/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "assignee",
    "plural": false,
    "selections": [
      (v5/*: any*/),
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
        "type": "Mannequin",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v43/*: any*/),
        "type": "Organization",
        "abstractKey": null
      },
      (v15/*: any*/)
    ],
    "storageKey": null
  },
  (v13/*: any*/)
],
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v45/*: any*/),
    (v18/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v47 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/),
    (v6/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v21/*: any*/),
    (v18/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v50 = [
  (v19/*: any*/),
  (v13/*: any*/),
  (v47/*: any*/)
],
v51 = {
  "kind": "InlineFragment",
  "selections": [
    (v37/*: any*/),
    (v41/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v52 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v21/*: any*/),
    (v32/*: any*/),
    (v7/*: any*/)
  ],
  "storageKey": null
},
v53 = [
  (v13/*: any*/),
  (v19/*: any*/),
  (v47/*: any*/)
],
v54 = [
  (v13/*: any*/),
  (v19/*: any*/),
  (v47/*: any*/),
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
      (v18/*: any*/),
      (v7/*: any*/)
    ],
    "storageKey": null
  }
],
v55 = [
  (v13/*: any*/),
  (v47/*: any*/),
  (v19/*: any*/),
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
          (v45/*: any*/),
          (v18/*: any*/),
          (v17/*: any*/),
          (v30/*: any*/),
          (v39/*: any*/),
          (v40/*: any*/),
          (v52/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v15/*: any*/)
    ],
    "storageKey": null
  }
],
v56 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v34/*: any*/),
        (v18/*: any*/),
        (v35/*: any*/),
        (v36/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v38/*: any*/),
        (v18/*: any*/),
        (v30/*: any*/),
        (v39/*: any*/),
        (v40/*: any*/),
        (v36/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v57 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v58 = [
  (v51/*: any*/)
],
v59 = {
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
        (v5/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/)
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        (v15/*: any*/),
        (v16/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
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
                (v9/*: any*/),
                (v7/*: any*/),
                (v17/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "locked",
                  "storageKey": null
                },
                (v13/*: any*/)
              ],
              "storageKey": null
            },
            (v7/*: any*/),
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
            (v18/*: any*/),
            (v19/*: any*/),
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
                (v19/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "isActive",
                  "storageKey": null
                },
                (v7/*: any*/)
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
                (v7/*: any*/),
                (v6/*: any*/),
                (v20/*: any*/)
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
                (v7/*: any*/),
                (v21/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "owner",
                  "plural": false,
                  "selections": [
                    (v5/*: any*/),
                    (v7/*: any*/),
                    (v6/*: any*/),
                    (v18/*: any*/)
                  ],
                  "storageKey": null
                },
                (v22/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "slashCommandsEnabled",
                  "storageKey": null
                },
                (v23/*: any*/),
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
                        (v5/*: any*/),
                        (v18/*: any*/),
                        (v6/*: any*/),
                        (v7/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v7/*: any*/)
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
                        (v12/*: any*/),
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
                              "selections": (v24/*: any*/),
                              "type": "User",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": (v24/*: any*/),
                              "type": "Bot",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": (v24/*: any*/),
                              "type": "Organization",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": (v24/*: any*/),
                              "type": "Mannequin",
                              "abstractKey": null
                            },
                            (v15/*: any*/)
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
            (v19/*: any*/),
            (v27/*: any*/),
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
              "selections": (v28/*: any*/),
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
                (v18/*: any*/),
                (v29/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "signature",
                  "plural": false,
                  "selections": [
                    (v5/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "User",
                      "kind": "LinkedField",
                      "name": "signer",
                      "plural": false,
                      "selections": [
                        (v6/*: any*/),
                        (v20/*: any*/),
                        (v7/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v30/*: any*/),
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
                          "selections": (v31/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v31/*: any*/),
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
                    (v21/*: any*/),
                    (v32/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "defaultBranch",
                      "storageKey": null
                    },
                    (v7/*: any*/)
                  ],
                  "storageKey": null
                },
                (v7/*: any*/)
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
            (v19/*: any*/),
            (v27/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "source",
              "plural": false,
              "selections": (v28/*: any*/),
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
                (v5/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v33/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v15/*: any*/)
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
                (v5/*: any*/),
                {
                  "kind": "TypeDiscriminator",
                  "abstractKey": "__isReferencedSubject"
                },
                (v37/*: any*/),
                (v41/*: any*/),
                (v15/*: any*/)
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
            (v27/*: any*/),
            (v19/*: any*/),
            (v13/*: any*/)
          ],
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v42/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v42/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v44/*: any*/),
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v44/*: any*/),
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v27/*: any*/),
            (v13/*: any*/),
            (v46/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v27/*: any*/),
            (v46/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v47/*: any*/),
            (v48/*: any*/),
            (v49/*: any*/),
            (v13/*: any*/)
          ],
          "type": "AddedToProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v13/*: any*/),
            (v47/*: any*/),
            (v48/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "previousProjectColumnName",
              "storageKey": null
            },
            (v49/*: any*/)
          ],
          "type": "MovedColumnsInProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v13/*: any*/),
            (v47/*: any*/),
            (v48/*: any*/),
            (v49/*: any*/)
          ],
          "type": "RemovedFromProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v50/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v50/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v19/*: any*/),
            (v35/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v5/*: any*/),
                (v51/*: any*/),
                (v15/*: any*/)
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
                    (v18/*: any*/),
                    (v45/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v18/*: any*/),
                    (v17/*: any*/),
                    (v52/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v18/*: any*/),
                    (v29/*: any*/),
                    (v52/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v15/*: any*/)
              ],
              "storageKey": null
            },
            (v47/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v53/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v47/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v53/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v53/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v53/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v19/*: any*/),
            (v47/*: any*/),
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
            (v19/*: any*/),
            (v47/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "deletedCommentAuthor",
              "plural": false,
              "selections": (v8/*: any*/),
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
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v47/*: any*/),
            {
              "alias": "blockedUser",
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": [
                (v6/*: any*/),
                (v7/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UserBlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v54/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v54/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v55/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v47/*: any*/),
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v23/*: any*/),
                (v18/*: any*/),
                (v7/*: any*/)
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
            (v13/*: any*/),
            (v47/*: any*/),
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Project",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v18/*: any*/),
                (v21/*: any*/),
                (v7/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "ConvertedNoteToIssueEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v55/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v47/*: any*/),
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v5/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v7/*: any*/),
                    (v17/*: any*/),
                    (v56/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v17/*: any*/),
                    (v7/*: any*/),
                    (v56/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v15/*: any*/)
              ],
              "storageKey": null
            },
            (v57/*: any*/),
            (v13/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanUndo",
              "storageKey": null
            },
            (v7/*: any*/),
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
            (v47/*: any*/),
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v5/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v58/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v58/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v15/*: any*/)
              ],
              "storageKey": null
            },
            (v57/*: any*/),
            (v13/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v13/*: any*/),
            (v47/*: any*/),
            (v19/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v18/*: any*/),
                (v17/*: any*/),
                (v7/*: any*/)
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
            (v19/*: any*/),
            (v47/*: any*/),
            (v46/*: any*/),
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
            (v19/*: any*/),
            (v47/*: any*/),
            (v13/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        }
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
v60 = [
  "visibleEventsOnly"
],
v61 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v10/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTimelineTestSharedQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": [
                  {
                    "kind": "Literal",
                    "name": "numberOfTimelineItems",
                    "value": 25
                  }
                ],
                "kind": "FragmentSpread",
                "name": "IssueTimelinePaginated"
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
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueTimelineTestSharedQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v9/*: any*/),
              {
                "alias": "frontTimeline",
                "args": (v11/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v12/*: any*/),
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
                  (v59/*: any*/),
                  (v16/*: any*/)
                ],
                "storageKey": "timelineItems(first:25,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimeline",
                "args": (v11/*: any*/),
                "filters": (v60/*: any*/),
                "handle": "connection",
                "key": "Issue_frontTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              (v7/*: any*/),
              (v18/*: any*/),
              (v33/*: any*/),
              {
                "alias": null,
                "args": (v61/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v12/*: any*/),
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
                  (v59/*: any*/),
                  (v16/*: any*/)
                ],
                "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
              },
              {
                "alias": null,
                "args": (v61/*: any*/),
                "filters": (v60/*: any*/),
                "handle": "connection",
                "key": "IssueBacksideTimeline_timelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              }
            ],
            "storageKey": null
          },
          (v7/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "3c05d19236e378ccbbfc359920c6d562",
    "metadata": {},
    "name": "IssueTimelineTestSharedQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "bf916873447e9c16032f08f3acb95457";

export default node;
