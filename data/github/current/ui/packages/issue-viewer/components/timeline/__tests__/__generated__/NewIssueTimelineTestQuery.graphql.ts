/**
 * @generated SignedSource<<5f53942f89c18d9a87a59e8d2f695162>>
 * @relayHash b9fac6c72d20489e9129275ab5114738
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b9fac6c72d20489e9129275ab5114738

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type NewIssueTimelineTestQuery$variables = Record<PropertyKey, never>;
export type NewIssueTimelineTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"NewIssueTimelineIssueFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type NewIssueTimelineTestQuery = {
  response: NewIssueTimelineTestQuery$data;
  variables: NewIssueTimelineTestQuery$variables;
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
v4 = [
  (v2/*: any*/)
],
v5 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v4/*: any*/),
  "storageKey": null
},
v6 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v7 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v6/*: any*/)
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v13 = [
  (v9/*: any*/),
  (v12/*: any*/),
  (v2/*: any*/)
],
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v19 = [
  (v12/*: any*/)
],
v20 = {
  "kind": "InlineFragment",
  "selections": (v4/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v21 = [
  (v9/*: any*/),
  (v20/*: any*/)
],
v22 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v23 = {
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
v24 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v13/*: any*/),
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
    (v2/*: any*/),
    (v16/*: any*/),
    (v17/*: any*/),
    (v24/*: any*/)
  ],
  "storageKey": null
},
v26 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v22/*: any*/),
    (v3/*: any*/),
    (v14/*: any*/),
    (v23/*: any*/),
    (v25/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v27 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v31 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v27/*: any*/),
    (v3/*: any*/),
    (v14/*: any*/),
    (v28/*: any*/),
    (v29/*: any*/),
    (v30/*: any*/),
    (v25/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v32 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
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
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    (v32/*: any*/),
    (v33/*: any*/),
    (v12/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v35 = [
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
      (v16/*: any*/),
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
  (v10/*: any*/),
  (v11/*: any*/),
  (v34/*: any*/)
],
v36 = [
  (v2/*: any*/),
  (v12/*: any*/)
],
v37 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "assignee",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": (v36/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v36/*: any*/),
      "type": "Bot",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v36/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v36/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    (v20/*: any*/)
  ],
  "storageKey": null
},
v38 = [
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
  (v10/*: any*/),
  (v11/*: any*/),
  (v34/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v39 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v16/*: any*/),
    (v3/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v41 = [
  (v11/*: any*/),
  (v10/*: any*/),
  (v34/*: any*/)
],
v42 = {
  "kind": "InlineFragment",
  "selections": [
    (v26/*: any*/),
    (v31/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v16/*: any*/),
    (v24/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v46 = [
  (v10/*: any*/),
  (v11/*: any*/),
  (v34/*: any*/)
],
v47 = [
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
v48 = [
  (v10/*: any*/),
  (v34/*: any*/),
  (v11/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v9/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v43/*: any*/),
          (v3/*: any*/),
          (v14/*: any*/),
          (v28/*: any*/),
          (v29/*: any*/),
          (v30/*: any*/),
          (v44/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v20/*: any*/)
    ],
    "storageKey": null
  }
],
v49 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v22/*: any*/),
        (v3/*: any*/),
        (v23/*: any*/),
        (v25/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v27/*: any*/),
        (v3/*: any*/),
        (v28/*: any*/),
        (v29/*: any*/),
        (v30/*: any*/),
        (v25/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v51 = [
  (v42/*: any*/)
],
v52 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v43/*: any*/),
    (v3/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v53 = {
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
        (v9/*: any*/),
        {
          "kind": "TypeDiscriminator",
          "abstractKey": "__isIssueTimelineItems"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": (v13/*: any*/),
              "storageKey": null
            }
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
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
                  "selections": (v13/*: any*/),
                  "storageKey": null
                },
                (v2/*: any*/),
                (v14/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "locked",
                  "storageKey": null
                },
                (v10/*: any*/)
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
            (v11/*: any*/),
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
                (v11/*: any*/),
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
              "concreteType": null,
              "kind": "LinkedField",
              "name": "author",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                (v2/*: any*/),
                (v12/*: any*/),
                (v15/*: any*/)
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
                (v16/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "owner",
                  "plural": false,
                  "selections": [
                    (v9/*: any*/),
                    (v2/*: any*/),
                    (v12/*: any*/),
                    (v3/*: any*/)
                  ],
                  "storageKey": null
                },
                (v17/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "slashCommandsEnabled",
                  "storageKey": null
                },
                (v18/*: any*/),
                (v10/*: any*/)
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
                        (v9/*: any*/),
                        (v3/*: any*/),
                        (v12/*: any*/),
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
                        (v8/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "nodes",
                          "plural": true,
                          "selections": [
                            (v9/*: any*/),
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
                              "type": "Organization",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": (v19/*: any*/),
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
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "target",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v5/*: any*/)
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
                (v9/*: any*/),
                {
                  "kind": "TypeDiscriminator",
                  "abstractKey": "__isReferencedSubject"
                },
                (v26/*: any*/),
                (v31/*: any*/),
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v34/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v35/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v35/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v37/*: any*/),
            (v10/*: any*/),
            (v11/*: any*/),
            (v34/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v37/*: any*/),
            (v10/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                (v12/*: any*/),
                (v32/*: any*/),
                (v33/*: any*/),
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
          "selections": (v38/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v38/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v34/*: any*/),
            (v39/*: any*/),
            (v40/*: any*/),
            (v10/*: any*/)
          ],
          "type": "AddedToProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v10/*: any*/),
            (v34/*: any*/),
            (v39/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "previousProjectColumnName",
              "storageKey": null
            },
            (v40/*: any*/)
          ],
          "type": "MovedColumnsInProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v10/*: any*/),
            (v34/*: any*/),
            (v39/*: any*/),
            (v40/*: any*/)
          ],
          "type": "RemovedFromProjectEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v41/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v41/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v41/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v11/*: any*/),
            (v23/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                (v42/*: any*/),
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
                (v9/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v43/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v14/*: any*/),
                    (v44/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v45/*: any*/),
                    (v44/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v34/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v46/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v34/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v46/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v46/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v46/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v11/*: any*/),
            (v34/*: any*/),
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
            (v10/*: any*/),
            (v11/*: any*/),
            (v34/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "deletedCommentAuthor",
              "plural": false,
              "selections": (v13/*: any*/),
              "storageKey": null
            }
          ],
          "type": "CommentDeletedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v34/*: any*/),
            {
              "alias": "blockedUser",
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": [
                (v12/*: any*/),
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
          "selections": [
            (v10/*: any*/),
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
            (v34/*: any*/),
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
                (v45/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "signature",
                  "plural": false,
                  "selections": [
                    (v9/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "User",
                      "kind": "LinkedField",
                      "name": "signer",
                      "plural": false,
                      "selections": [
                        (v12/*: any*/),
                        (v15/*: any*/),
                        (v2/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v28/*: any*/),
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
                          "selections": (v47/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v47/*: any*/),
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
                    (v16/*: any*/),
                    (v24/*: any*/),
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
            (v11/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v48/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v34/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v18/*: any*/),
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
          "selections": [
            (v10/*: any*/),
            (v34/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Project",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v3/*: any*/),
                (v16/*: any*/),
                (v2/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "ConvertedNoteToIssueEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v48/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v34/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v2/*: any*/),
                    (v14/*: any*/),
                    (v49/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v14/*: any*/),
                    (v2/*: any*/),
                    (v49/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v50/*: any*/),
            (v10/*: any*/),
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
            (v34/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v51/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v51/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v20/*: any*/)
              ],
              "storageKey": null
            },
            (v50/*: any*/),
            (v10/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v10/*: any*/),
            (v34/*: any*/),
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v3/*: any*/),
                (v14/*: any*/),
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
            (v10/*: any*/),
            (v11/*: any*/),
            (v34/*: any*/),
            (v52/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v34/*: any*/),
            (v52/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v11/*: any*/),
            (v34/*: any*/),
            (v52/*: any*/),
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
            (v11/*: any*/),
            (v34/*: any*/),
            (v10/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
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
v54 = [
  "visibleEventsOnly"
],
v55 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 15
  },
  (v6/*: any*/)
],
v56 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v57 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueTimelineItemsConnection"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "IssueTimelineItemsEdge"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v61 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueTimelineItems"
},
v62 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v63 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v64 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Assignee"
},
v65 = {
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
v66 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Sponsorship"
},
v67 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v68 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v69 = {
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
v70 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v71 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v72 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v73 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v74 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v75 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v76 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v77 = {
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
v78 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Closer"
},
v79 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v80 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Commit"
},
v81 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitSignature"
},
v82 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v83 = {
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
v84 = {
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
v85 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v86 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Discussion"
},
v87 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v88 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v89 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Issue"
},
v90 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Label"
},
v91 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v92 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "UserContentEdit"
},
v93 = {
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
v94 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Milestone"
},
v95 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Project"
},
v96 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "ReactionGroup"
},
v97 = {
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
v98 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReactorConnection"
},
v99 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Reactor"
},
v100 = {
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
    "name": "NewIssueTimelineTestQuery",
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
                "name": "NewIssueTimelineIssueFragment"
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
    "name": "NewIssueTimelineTestQuery",
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
              (v5/*: any*/),
              {
                "alias": "frontTimelineItems",
                "args": (v7/*: any*/),
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
                  (v8/*: any*/),
                  (v53/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v7/*: any*/),
                "filters": (v54/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v55/*: any*/),
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
                  (v8/*: any*/),
                  (v53/*: any*/)
                ],
                "storageKey": "timelineItems(last:15,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v55/*: any*/),
                "filters": (v54/*: any*/),
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
    "id": "b9fac6c72d20489e9129275ab5114738",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": (v56/*: any*/),
        "repository.id": (v57/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.backTimelineItems": (v58/*: any*/),
        "repository.issue.backTimelineItems.edges": (v59/*: any*/),
        "repository.issue.backTimelineItems.edges.cursor": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node": (v61/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isComment": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isIssueTimelineItems": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isReactable": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__isTimelineEvent": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor": (v62/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__isActor": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.avatarUrl": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.actor.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee": (v64/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.assignee.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author": (v62/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.avatarUrl": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.author.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorAssociation": (v65/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v66/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v67/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockDuration": (v69/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.blockedUser.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.body": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyHTML": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.bodyVersion": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__isReferencedSubject": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isDraft": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.isInMergeQueue": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.issueTitleHTML": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.pullTitleHTML": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.isPrivate": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.state": (v76/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.stateReason": (v77/*: any*/),
        "repository.issue.backTimelineItems.edges.node.canonical.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer": (v78/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.abbreviatedOid": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.title": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closer.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.closingProjectItemStatus": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit": (v80/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.abbreviatedOid": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.hasSignature": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.message": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageBodyHTML": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.messageHeadlineHTML": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.defaultBranch": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature": (v81/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.commonName": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organization": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyFingerprint": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.keyId": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer": (v70/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.signer.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.state": (v83/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject": (v82/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.commonName": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.emailAddress": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organization": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.commit.verificationStatus": (v84/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdAt": (v67/*: any*/),
        "repository.issue.backTimelineItems.edges.node.createdViaEmail": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.currentTitle": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.databaseId": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor": (v62/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.deletedCommentAuthor.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion": (v86/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.discussion.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf": (v72/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isDraft": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.state": (v76/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.stateReason": (v77/*: any*/),
        "repository.issue.backTimelineItems.edges.node.duplicateOf.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository": (v56/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.nameWithOwner": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.fromRepository.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__isReferencedSubject": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isDraft": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.isInMergeQueue": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.issueTitleHTML": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.pullTitleHTML": (v71/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.isPrivate": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.state": (v76/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.stateReason": (v77/*: any*/),
        "repository.issue.backTimelineItems.edges.node.innerSource.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.isHidden": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue": (v89/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author": (v62/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.author.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.databaseId": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.locked": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.issue.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label": (v90/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.color": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.description": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.label.nameHTML": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastEditedAt": (v91/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit": (v92/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor": (v62/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.editor.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lastUserContentEdit.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.lockReason": (v93/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone": (v94/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestone.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.milestoneTitle": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.minimizedReason": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingBlock": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingMinimizeReason": (v79/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUnblock": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.pendingUndo": (v88/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousProjectColumnName": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousStatus": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.previousTitle": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project": (v95/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.title": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.project.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.projectColumnName": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups": (v96/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.content": (v97/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors": (v98/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes": (v99/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.referencedAt": (v67/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.databaseId": (v85/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.isPrivate": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.nameWithOwner": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.owner.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.repository.slashCommandsEnabled": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.showSpammyBadge": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.source.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.stateReason": (v77/*: any*/),
        "repository.issue.backTimelineItems.edges.node.status": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isDraft": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.isInMergeQueue": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.number": (v73/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.name": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner": (v75/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.repository.owner.login": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.state": (v76/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.title": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.subject.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target": (v87/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__isNode": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.__typename": (v60/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository": (v74/*: any*/),
        "repository.issue.backTimelineItems.edges.node.target.repository.id": (v57/*: any*/),
        "repository.issue.backTimelineItems.edges.node.url": (v63/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanBlockFromOrg": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanDelete": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanMinimize": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReadUserContentEdits": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReport": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanReportToMaintainer": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUnblockFromOrg": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUndo": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerCanUpdate": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.viewerDidAuthor": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseSubject": (v68/*: any*/),
        "repository.issue.backTimelineItems.edges.node.willCloseTarget": (v68/*: any*/),
        "repository.issue.backTimelineItems.pageInfo": (v100/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.hasPreviousPage": (v68/*: any*/),
        "repository.issue.backTimelineItems.pageInfo.startCursor": (v79/*: any*/),
        "repository.issue.backTimelineItems.totalCount": (v73/*: any*/),
        "repository.issue.frontTimelineItems": (v58/*: any*/),
        "repository.issue.frontTimelineItems.edges": (v59/*: any*/),
        "repository.issue.frontTimelineItems.edges.cursor": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node": (v61/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isComment": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isIssueTimelineItems": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isReactable": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__isTimelineEvent": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor": (v62/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__isActor": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.avatarUrl": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.actor.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee": (v64/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.assignee.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author": (v62/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.avatarUrl": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.author.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorAssociation": (v65/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship": (v66/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.createdAt": (v67/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.authorToRepoOwnerSponsorship.isActive": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockDuration": (v69/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.blockedUser.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.body": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyHTML": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.bodyVersion": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__isReferencedSubject": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isDraft": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.isInMergeQueue": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.issueTitleHTML": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.pullTitleHTML": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.isPrivate": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.state": (v76/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.stateReason": (v77/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.canonical.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer": (v78/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.abbreviatedOid": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.title": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closer.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.closingProjectItemStatus": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit": (v80/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.abbreviatedOid": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.hasSignature": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.message": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageBodyHTML": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.messageHeadlineHTML": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.defaultBranch": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature": (v81/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.commonName": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.emailAddress": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organization": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.issuer.organizationUnit": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyFingerprint": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.keyId": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer": (v70/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.avatarUrl": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.signer.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.state": (v83/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject": (v82/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.commonName": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.emailAddress": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organization": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.subject.organizationUnit": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.signature.wasSignedByGitHub": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.commit.verificationStatus": (v84/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdAt": (v67/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.createdViaEmail": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.currentTitle": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.databaseId": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor": (v62/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.deletedCommentAuthor.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion": (v86/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.discussion.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf": (v72/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__isReferencedSubject": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isDraft": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.isInMergeQueue": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.issueTitleHTML": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.pullTitleHTML": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.isPrivate": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.state": (v76/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.stateReason": (v77/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.duplicateOf.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository": (v56/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.nameWithOwner": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.fromRepository.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__isReferencedSubject": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isDraft": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.isInMergeQueue": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.issueTitleHTML": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.pullTitleHTML": (v71/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.isPrivate": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.state": (v76/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.stateReason": (v77/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.innerSource.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isCanonicalOfClosedDuplicate": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.isHidden": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue": (v89/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author": (v62/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.author.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.databaseId": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.locked": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.issue.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label": (v90/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.color": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.description": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.label.nameHTML": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastEditedAt": (v91/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit": (v92/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor": (v62/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.editor.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lastUserContentEdit.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.lockReason": (v93/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone": (v94/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestone.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.milestoneTitle": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.minimizedReason": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingBlock": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingMinimizeReason": (v79/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUnblock": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.pendingUndo": (v88/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousProjectColumnName": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousStatus": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.previousTitle": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project": (v95/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.title": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.project.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.projectColumnName": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups": (v96/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.content": (v97/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors": (v98/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes": (v99/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.nodes.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.reactors.totalCount": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.reactionGroups.viewerHasReacted": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.referencedAt": (v67/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.databaseId": (v85/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.isPrivate": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.nameWithOwner": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.owner.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.repository.slashCommandsEnabled": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.showSpammyBadge": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.source.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.stateReason": (v77/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.status": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isDraft": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.isInMergeQueue": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.number": (v73/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.name": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner": (v75/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.repository.owner.login": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.state": (v76/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.title": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.subject.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target": (v87/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__isNode": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.__typename": (v60/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository": (v74/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.target.repository.id": (v57/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.url": (v63/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanBlockFromOrg": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanDelete": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanMinimize": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReadUserContentEdits": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReport": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanReportToMaintainer": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUnblockFromOrg": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUndo": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerCanUpdate": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.viewerDidAuthor": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseSubject": (v68/*: any*/),
        "repository.issue.frontTimelineItems.edges.node.willCloseTarget": (v68/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo": (v100/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.endCursor": (v79/*: any*/),
        "repository.issue.frontTimelineItems.pageInfo.hasNextPage": (v68/*: any*/),
        "repository.issue.frontTimelineItems.totalCount": (v73/*: any*/),
        "repository.issue.id": (v57/*: any*/),
        "repository.issue.repository": (v74/*: any*/),
        "repository.issue.repository.id": (v57/*: any*/),
        "repository.issue.url": (v63/*: any*/)
      }
    },
    "name": "NewIssueTimelineTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "8a9220acf9a4ae2befea49926a5c3338";

export default node;
