/**
 * @generated SignedSource<<15a81105442ab09dd9307d91315e9165>>
 * @relayHash d4d942e30ff9f2773ee7d68147091b96
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d4d942e30ff9f2773ee7d68147091b96

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type TimelinePaginationQuery$variables = {
  cursor?: string | null | undefined;
  id: string;
  numberOfTimelineItems?: number | null | undefined;
};
export type TimelinePaginationQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineFrontPaginated">;
  } | null | undefined;
};
export type TimelinePaginationQuery = {
  response: TimelinePaginationQuery$data;
  variables: TimelinePaginationQuery$variables;
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
  "name": "numberOfTimelineItems"
},
v3 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v6 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "cursor"
  },
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "numberOfTimelineItems"
  },
  {
    "kind": "Literal",
    "name": "visibleEventsOnly",
    "value": true
  }
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
  "name": "databaseId",
  "storageKey": null
},
v9 = [
  (v5/*: any*/)
],
v10 = {
  "kind": "InlineFragment",
  "selections": (v9/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v11 = {
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
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v13 = [
  (v4/*: any*/),
  (v12/*: any*/),
  (v5/*: any*/)
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
  "name": "url",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v21 = [
  (v12/*: any*/)
],
v22 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v23 = {
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
v24 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v4/*: any*/),
    (v12/*: any*/),
    (v5/*: any*/),
    (v22/*: any*/),
    (v23/*: any*/)
  ],
  "storageKey": null
},
v25 = [
  (v4/*: any*/),
  (v10/*: any*/)
],
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v28 = [
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
v29 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v13/*: any*/),
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v9/*: any*/),
  "storageKey": null
},
v31 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v32 = {
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
v33 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v5/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/),
    (v29/*: any*/)
  ],
  "storageKey": null
},
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v5/*: any*/),
    (v31/*: any*/),
    (v15/*: any*/),
    (v14/*: any*/),
    (v32/*: any*/),
    (v33/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v35 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v38 = {
  "kind": "InlineFragment",
  "selections": [
    (v5/*: any*/),
    (v35/*: any*/),
    (v15/*: any*/),
    (v14/*: any*/),
    (v27/*: any*/),
    (v36/*: any*/),
    (v37/*: any*/),
    (v33/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v39 = [
  (v16/*: any*/),
  (v24/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v5/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v18/*: any*/),
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
  (v8/*: any*/)
],
v40 = [
  (v5/*: any*/),
  (v12/*: any*/)
],
v41 = [
  (v16/*: any*/),
  (v24/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "assignee",
    "plural": false,
    "selections": [
      (v4/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": (v40/*: any*/),
        "type": "User",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v40/*: any*/),
        "type": "Bot",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v40/*: any*/),
        "type": "Mannequin",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v40/*: any*/),
        "type": "Organization",
        "abstractKey": null
      },
      (v10/*: any*/)
    ],
    "storageKey": null
  },
  (v8/*: any*/)
],
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v42/*: any*/),
    (v15/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v4/*: any*/),
    (v22/*: any*/),
    (v23/*: any*/),
    (v12/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v18/*: any*/),
    (v15/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v47 = [
  (v16/*: any*/),
  (v8/*: any*/),
  (v44/*: any*/)
],
v48 = {
  "kind": "InlineFragment",
  "selections": [
    (v34/*: any*/),
    (v38/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v49 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v18/*: any*/),
    (v29/*: any*/),
    (v5/*: any*/)
  ],
  "storageKey": null
},
v50 = [
  (v8/*: any*/),
  (v16/*: any*/),
  (v44/*: any*/)
],
v51 = [
  (v8/*: any*/),
  (v16/*: any*/),
  (v44/*: any*/),
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
      (v15/*: any*/),
      (v5/*: any*/)
    ],
    "storageKey": null
  }
],
v52 = [
  (v8/*: any*/),
  (v44/*: any*/),
  (v16/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v4/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v42/*: any*/),
          (v15/*: any*/),
          (v14/*: any*/),
          (v27/*: any*/),
          (v36/*: any*/),
          (v37/*: any*/),
          (v49/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v10/*: any*/)
    ],
    "storageKey": null
  }
],
v53 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v31/*: any*/),
        (v15/*: any*/),
        (v32/*: any*/),
        (v33/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v35/*: any*/),
        (v15/*: any*/),
        (v27/*: any*/),
        (v36/*: any*/),
        (v37/*: any*/),
        (v33/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v54 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v55 = [
  (v48/*: any*/)
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
    "name": "TimelinePaginationQuery",
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
              {
                "kind": "Variable",
                "name": "numberOfTimelineItems",
                "variableName": "numberOfTimelineItems"
              }
            ],
            "kind": "FragmentSpread",
            "name": "IssueTimelineFrontPaginated"
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
    "name": "TimelinePaginationQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          (v5/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": "frontTimeline",
                "args": (v6/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v7/*: any*/),
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
                  {
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
                          (v4/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/)
                            ],
                            "type": "TimelineEvent",
                            "abstractKey": "__isTimelineEvent"
                          },
                          (v10/*: any*/),
                          (v11/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
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
                                  (v5/*: any*/),
                                  (v14/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "locked",
                                    "storageKey": null
                                  },
                                  (v8/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v5/*: any*/),
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
                              (v15/*: any*/),
                              (v16/*: any*/),
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
                                  (v16/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "isActive",
                                    "storageKey": null
                                  },
                                  (v5/*: any*/)
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
                                  (v4/*: any*/),
                                  (v5/*: any*/),
                                  (v12/*: any*/),
                                  (v17/*: any*/)
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
                                  (v5/*: any*/),
                                  (v18/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "owner",
                                    "plural": false,
                                    "selections": [
                                      (v4/*: any*/),
                                      (v5/*: any*/),
                                      (v12/*: any*/),
                                      (v15/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v19/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slashCommandsEnabled",
                                    "storageKey": null
                                  },
                                  (v20/*: any*/),
                                  (v8/*: any*/)
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
                                          (v4/*: any*/),
                                          (v15/*: any*/),
                                          (v12/*: any*/),
                                          (v5/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v5/*: any*/)
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
                                              (v4/*: any*/),
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v21/*: any*/),
                                                "type": "User",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v21/*: any*/),
                                                "type": "Bot",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v21/*: any*/),
                                                "type": "Organization",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v21/*: any*/),
                                                "type": "Mannequin",
                                                "abstractKey": null
                                              },
                                              (v10/*: any*/)
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
                              (v16/*: any*/),
                              (v24/*: any*/),
                              (v8/*: any*/),
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
                                "selections": (v25/*: any*/),
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
                                  (v15/*: any*/),
                                  (v26/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "signature",
                                    "plural": false,
                                    "selections": [
                                      (v4/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": "User",
                                        "kind": "LinkedField",
                                        "name": "signer",
                                        "plural": false,
                                        "selections": [
                                          (v12/*: any*/),
                                          (v17/*: any*/),
                                          (v5/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v27/*: any*/),
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
                                            "selections": (v28/*: any*/),
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "CertificateAttributes",
                                            "kind": "LinkedField",
                                            "name": "subject",
                                            "plural": false,
                                            "selections": (v28/*: any*/),
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
                                      (v18/*: any*/),
                                      (v29/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "defaultBranch",
                                        "storageKey": null
                                      },
                                      (v5/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v5/*: any*/)
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
                              (v16/*: any*/),
                              (v24/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "source",
                                "plural": false,
                                "selections": (v25/*: any*/),
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
                              (v8/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "target",
                                "plural": false,
                                "selections": [
                                  (v4/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v30/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  (v10/*: any*/)
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
                                  (v4/*: any*/),
                                  {
                                    "kind": "TypeDiscriminator",
                                    "abstractKey": "__isReferencedSubject"
                                  },
                                  (v34/*: any*/),
                                  (v38/*: any*/),
                                  (v10/*: any*/)
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
                              (v24/*: any*/),
                              (v16/*: any*/),
                              (v8/*: any*/)
                            ],
                            "type": "MentionedEvent",
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
                            "selections": (v41/*: any*/),
                            "type": "AssignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v41/*: any*/),
                            "type": "UnassignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v16/*: any*/),
                              (v24/*: any*/),
                              (v8/*: any*/),
                              (v43/*: any*/)
                            ],
                            "type": "AddedToProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v16/*: any*/),
                              (v24/*: any*/),
                              (v43/*: any*/)
                            ],
                            "type": "RemovedFromProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v16/*: any*/),
                              (v44/*: any*/),
                              (v45/*: any*/),
                              (v46/*: any*/),
                              (v8/*: any*/)
                            ],
                            "type": "AddedToProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v16/*: any*/),
                              (v8/*: any*/),
                              (v44/*: any*/),
                              (v45/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "previousProjectColumnName",
                                "storageKey": null
                              },
                              (v46/*: any*/)
                            ],
                            "type": "MovedColumnsInProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v16/*: any*/),
                              (v8/*: any*/),
                              (v44/*: any*/),
                              (v45/*: any*/),
                              (v46/*: any*/)
                            ],
                            "type": "RemovedFromProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v47/*: any*/),
                            "type": "SubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v47/*: any*/),
                            "type": "UnsubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v16/*: any*/),
                              (v32/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "duplicateOf",
                                "plural": false,
                                "selections": [
                                  (v4/*: any*/),
                                  (v48/*: any*/),
                                  (v10/*: any*/)
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
                                  (v4/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v15/*: any*/),
                                      (v42/*: any*/)
                                    ],
                                    "type": "ProjectV2",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v15/*: any*/),
                                      (v14/*: any*/),
                                      (v49/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v15/*: any*/),
                                      (v26/*: any*/),
                                      (v49/*: any*/)
                                    ],
                                    "type": "Commit",
                                    "abstractKey": null
                                  },
                                  (v10/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v44/*: any*/)
                            ],
                            "type": "ClosedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v50/*: any*/),
                            "type": "ReopenedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "lockReason",
                                "storageKey": null
                              },
                              (v44/*: any*/)
                            ],
                            "type": "LockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v50/*: any*/),
                            "type": "UnlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v50/*: any*/),
                            "type": "PinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v50/*: any*/),
                            "type": "UnpinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v16/*: any*/),
                              (v44/*: any*/),
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
                              (v8/*: any*/),
                              (v16/*: any*/),
                              (v44/*: any*/),
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
                              (v8/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "blockDuration",
                                "storageKey": null
                              },
                              (v44/*: any*/),
                              {
                                "alias": "blockedUser",
                                "args": null,
                                "concreteType": "User",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  (v5/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "UserBlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v51/*: any*/),
                            "type": "MilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v51/*: any*/),
                            "type": "DemilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v52/*: any*/),
                            "type": "ConnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v44/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "fromRepository",
                                "plural": false,
                                "selections": [
                                  (v20/*: any*/),
                                  (v15/*: any*/),
                                  (v5/*: any*/)
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
                              (v8/*: any*/),
                              (v44/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Project",
                                "kind": "LinkedField",
                                "name": "project",
                                "plural": false,
                                "selections": [
                                  (v15/*: any*/),
                                  (v18/*: any*/),
                                  (v5/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "ConvertedNoteToIssueEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v52/*: any*/),
                            "type": "DisconnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v44/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "canonical",
                                "plural": false,
                                "selections": [
                                  (v4/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v5/*: any*/),
                                      (v14/*: any*/),
                                      (v53/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v14/*: any*/),
                                      (v5/*: any*/),
                                      (v53/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v10/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v54/*: any*/),
                              (v8/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUndo",
                                "storageKey": null
                              },
                              (v5/*: any*/),
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
                              (v44/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "canonical",
                                "plural": false,
                                "selections": [
                                  (v4/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v55/*: any*/),
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v55/*: any*/),
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v10/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v54/*: any*/),
                              (v8/*: any*/)
                            ],
                            "type": "UnmarkedAsDuplicateEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v8/*: any*/),
                              (v44/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Discussion",
                                "kind": "LinkedField",
                                "name": "discussion",
                                "plural": false,
                                "selections": [
                                  (v15/*: any*/),
                                  (v14/*: any*/),
                                  (v5/*: any*/)
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
                              (v16/*: any*/),
                              (v44/*: any*/),
                              (v43/*: any*/),
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
                              (v16/*: any*/),
                              (v44/*: any*/),
                              (v8/*: any*/)
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
                  (v11/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "frontTimeline",
                "args": (v6/*: any*/),
                "filters": [
                  "visibleEventsOnly"
                ],
                "handle": "connection",
                "key": "Issue_frontTimeline",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              (v15/*: any*/),
              (v30/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "d4d942e30ff9f2773ee7d68147091b96",
    "metadata": {},
    "name": "TimelinePaginationQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "100637e79fa0ed0f1b9b5e95deee0993";

export default node;
