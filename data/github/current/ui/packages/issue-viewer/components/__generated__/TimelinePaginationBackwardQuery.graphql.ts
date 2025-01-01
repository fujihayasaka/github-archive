/**
 * @generated SignedSource<<a79e6f492b3fc2cdad123a3a7773829e>>
 * @relayHash cb5836c08f541cda116f5087d899cc1f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID cb5836c08f541cda116f5087d899cc1f

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type TimelinePaginationBackwardQuery$variables = {
  after?: string | null | undefined;
  before?: string | null | undefined;
  first?: number | null | undefined;
  focusText?: string | null | undefined;
  id: string;
  last?: number | null | undefined;
};
export type TimelinePaginationBackwardQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"HighlightedTimelineBackwardPaginated">;
  } | null | undefined;
};
export type TimelinePaginationBackwardQuery = {
  response: TimelinePaginationBackwardQuery$data;
  variables: TimelinePaginationBackwardQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "after"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "before"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "focusText"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "last"
},
v6 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v7 = {
  "kind": "Variable",
  "name": "after",
  "variableName": "after"
},
v8 = {
  "kind": "Variable",
  "name": "before",
  "variableName": "before"
},
v9 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v10 = {
  "kind": "Variable",
  "name": "focusText",
  "variableName": "focusText"
},
v11 = {
  "kind": "Variable",
  "name": "last",
  "variableName": "last"
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v14 = [
  (v7/*: any*/),
  (v8/*: any*/),
  (v9/*: any*/),
  (v10/*: any*/),
  (v11/*: any*/),
  {
    "kind": "Literal",
    "name": "visibleEventsOnly",
    "value": true
  }
],
v15 = [
  (v13/*: any*/)
],
v16 = {
  "kind": "InlineFragment",
  "selections": (v15/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v17 = {
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
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v20 = [
  (v12/*: any*/),
  (v19/*: any*/),
  (v13/*: any*/)
],
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
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
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v28 = [
  (v19/*: any*/)
],
v29 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v30 = {
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
v31 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v19/*: any*/),
    (v13/*: any*/),
    (v29/*: any*/),
    (v30/*: any*/)
  ],
  "storageKey": null
},
v32 = [
  (v12/*: any*/),
  (v16/*: any*/)
],
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v35 = [
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
v36 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v20/*: any*/),
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v15/*: any*/),
  "storageKey": null
},
v38 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v39 = {
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
v40 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/),
    (v36/*: any*/)
  ],
  "storageKey": null
},
v41 = {
  "kind": "InlineFragment",
  "selections": [
    (v13/*: any*/),
    (v38/*: any*/),
    (v22/*: any*/),
    (v21/*: any*/),
    (v39/*: any*/),
    (v40/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v42 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v45 = {
  "kind": "InlineFragment",
  "selections": [
    (v13/*: any*/),
    (v42/*: any*/),
    (v22/*: any*/),
    (v21/*: any*/),
    (v34/*: any*/),
    (v43/*: any*/),
    (v44/*: any*/),
    (v40/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v46 = [
  (v23/*: any*/),
  (v31/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v13/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v25/*: any*/),
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
  (v18/*: any*/)
],
v47 = [
  (v13/*: any*/),
  (v19/*: any*/)
],
v48 = [
  (v23/*: any*/),
  (v31/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "assignee",
    "plural": false,
    "selections": [
      (v12/*: any*/),
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
        "type": "Mannequin",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": (v47/*: any*/),
        "type": "Organization",
        "abstractKey": null
      },
      (v16/*: any*/)
    ],
    "storageKey": null
  },
  (v18/*: any*/)
],
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v49/*: any*/),
    (v22/*: any*/),
    (v13/*: any*/)
  ],
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v29/*: any*/),
    (v30/*: any*/),
    (v19/*: any*/),
    (v13/*: any*/)
  ],
  "storageKey": null
},
v52 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v25/*: any*/),
    (v22/*: any*/),
    (v13/*: any*/)
  ],
  "storageKey": null
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v54 = [
  (v23/*: any*/),
  (v18/*: any*/),
  (v51/*: any*/)
],
v55 = {
  "kind": "InlineFragment",
  "selections": [
    (v41/*: any*/),
    (v45/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v56 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v25/*: any*/),
    (v36/*: any*/),
    (v13/*: any*/)
  ],
  "storageKey": null
},
v57 = [
  (v18/*: any*/),
  (v23/*: any*/),
  (v51/*: any*/)
],
v58 = [
  (v18/*: any*/),
  (v23/*: any*/),
  (v51/*: any*/),
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
      (v22/*: any*/),
      (v13/*: any*/)
    ],
    "storageKey": null
  }
],
v59 = [
  (v18/*: any*/),
  (v51/*: any*/),
  (v23/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v12/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v49/*: any*/),
          (v22/*: any*/),
          (v21/*: any*/),
          (v34/*: any*/),
          (v43/*: any*/),
          (v44/*: any*/),
          (v56/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v16/*: any*/)
    ],
    "storageKey": null
  }
],
v60 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v38/*: any*/),
        (v22/*: any*/),
        (v39/*: any*/),
        (v40/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v42/*: any*/),
        (v22/*: any*/),
        (v34/*: any*/),
        (v43/*: any*/),
        (v44/*: any*/),
        (v40/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v61 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v62 = [
  (v55/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "TimelinePaginationBackwardQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": [
              (v7/*: any*/),
              (v8/*: any*/),
              (v9/*: any*/),
              (v10/*: any*/),
              (v11/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "HighlightedTimelineBackwardPaginated"
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
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v5/*: any*/),
      (v4/*: any*/)
    ],
    "kind": "Operation",
    "name": "TimelinePaginationBackwardQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v12/*: any*/),
          (v13/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v14/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
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
                          (v12/*: any*/),
                          (v16/*: any*/),
                          (v17/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
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
                                    "selections": (v20/*: any*/),
                                    "storageKey": null
                                  },
                                  (v13/*: any*/),
                                  (v21/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "locked",
                                    "storageKey": null
                                  },
                                  (v18/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v13/*: any*/),
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
                              (v22/*: any*/),
                              (v23/*: any*/),
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
                                  (v23/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "isActive",
                                    "storageKey": null
                                  },
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
                                  (v12/*: any*/),
                                  (v13/*: any*/),
                                  (v19/*: any*/),
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
                                  (v13/*: any*/),
                                  (v25/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "owner",
                                    "plural": false,
                                    "selections": [
                                      (v12/*: any*/),
                                      (v13/*: any*/),
                                      (v19/*: any*/),
                                      (v22/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v26/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slashCommandsEnabled",
                                    "storageKey": null
                                  },
                                  (v27/*: any*/),
                                  (v18/*: any*/)
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
                                          (v12/*: any*/),
                                          (v22/*: any*/),
                                          (v19/*: any*/),
                                          (v13/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v13/*: any*/)
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
                                          {
                                            "alias": null,
                                            "args": null,
                                            "kind": "ScalarField",
                                            "name": "totalCount",
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": null,
                                            "kind": "LinkedField",
                                            "name": "nodes",
                                            "plural": true,
                                            "selections": [
                                              (v12/*: any*/),
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v28/*: any*/),
                                                "type": "User",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v28/*: any*/),
                                                "type": "Bot",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v28/*: any*/),
                                                "type": "Organization",
                                                "abstractKey": null
                                              },
                                              {
                                                "kind": "InlineFragment",
                                                "selections": (v28/*: any*/),
                                                "type": "Mannequin",
                                                "abstractKey": null
                                              },
                                              (v16/*: any*/)
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
                              (v23/*: any*/),
                              (v31/*: any*/),
                              (v18/*: any*/),
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
                                "selections": (v32/*: any*/),
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
                                  (v22/*: any*/),
                                  (v33/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": null,
                                    "kind": "LinkedField",
                                    "name": "signature",
                                    "plural": false,
                                    "selections": [
                                      (v12/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "concreteType": "User",
                                        "kind": "LinkedField",
                                        "name": "signer",
                                        "plural": false,
                                        "selections": [
                                          (v19/*: any*/),
                                          (v24/*: any*/),
                                          (v13/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v34/*: any*/),
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
                                            "selections": (v35/*: any*/),
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "CertificateAttributes",
                                            "kind": "LinkedField",
                                            "name": "subject",
                                            "plural": false,
                                            "selections": (v35/*: any*/),
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
                                      (v25/*: any*/),
                                      (v36/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "defaultBranch",
                                        "storageKey": null
                                      },
                                      (v13/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v13/*: any*/)
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
                              (v23/*: any*/),
                              (v31/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "source",
                                "plural": false,
                                "selections": (v32/*: any*/),
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
                              (v18/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "target",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v37/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  (v16/*: any*/)
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
                                  (v12/*: any*/),
                                  {
                                    "kind": "TypeDiscriminator",
                                    "abstractKey": "__isReferencedSubject"
                                  },
                                  (v41/*: any*/),
                                  (v45/*: any*/),
                                  (v16/*: any*/)
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
                              (v31/*: any*/),
                              (v23/*: any*/),
                              (v18/*: any*/)
                            ],
                            "type": "MentionedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v46/*: any*/),
                            "type": "LabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v46/*: any*/),
                            "type": "UnlabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v48/*: any*/),
                            "type": "AssignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v48/*: any*/),
                            "type": "UnassignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v23/*: any*/),
                              (v31/*: any*/),
                              (v18/*: any*/),
                              (v50/*: any*/)
                            ],
                            "type": "AddedToProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v23/*: any*/),
                              (v31/*: any*/),
                              (v50/*: any*/)
                            ],
                            "type": "RemovedFromProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v23/*: any*/),
                              (v51/*: any*/),
                              (v52/*: any*/),
                              (v53/*: any*/),
                              (v18/*: any*/)
                            ],
                            "type": "AddedToProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v23/*: any*/),
                              (v18/*: any*/),
                              (v51/*: any*/),
                              (v52/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "previousProjectColumnName",
                                "storageKey": null
                              },
                              (v53/*: any*/)
                            ],
                            "type": "MovedColumnsInProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v23/*: any*/),
                              (v18/*: any*/),
                              (v51/*: any*/),
                              (v52/*: any*/),
                              (v53/*: any*/)
                            ],
                            "type": "RemovedFromProjectEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v54/*: any*/),
                            "type": "SubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v54/*: any*/),
                            "type": "UnsubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
                              (v23/*: any*/),
                              (v39/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "duplicateOf",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  (v55/*: any*/),
                                  (v16/*: any*/)
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
                                  (v12/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v22/*: any*/),
                                      (v49/*: any*/)
                                    ],
                                    "type": "ProjectV2",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v22/*: any*/),
                                      (v21/*: any*/),
                                      (v56/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v22/*: any*/),
                                      (v33/*: any*/),
                                      (v56/*: any*/)
                                    ],
                                    "type": "Commit",
                                    "abstractKey": null
                                  },
                                  (v16/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v51/*: any*/)
                            ],
                            "type": "ClosedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v57/*: any*/),
                            "type": "ReopenedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "lockReason",
                                "storageKey": null
                              },
                              (v51/*: any*/)
                            ],
                            "type": "LockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v57/*: any*/),
                            "type": "UnlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v57/*: any*/),
                            "type": "PinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v57/*: any*/),
                            "type": "UnpinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
                              (v23/*: any*/),
                              (v51/*: any*/),
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
                              (v18/*: any*/),
                              (v23/*: any*/),
                              (v51/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "deletedCommentAuthor",
                                "plural": false,
                                "selections": (v20/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "CommentDeletedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "blockDuration",
                                "storageKey": null
                              },
                              (v51/*: any*/),
                              {
                                "alias": "blockedUser",
                                "args": null,
                                "concreteType": "User",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": [
                                  (v19/*: any*/),
                                  (v13/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "UserBlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v58/*: any*/),
                            "type": "MilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v58/*: any*/),
                            "type": "DemilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v59/*: any*/),
                            "type": "ConnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
                              (v51/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "fromRepository",
                                "plural": false,
                                "selections": [
                                  (v27/*: any*/),
                                  (v22/*: any*/),
                                  (v13/*: any*/)
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
                              (v18/*: any*/),
                              (v51/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Project",
                                "kind": "LinkedField",
                                "name": "project",
                                "plural": false,
                                "selections": [
                                  (v22/*: any*/),
                                  (v25/*: any*/),
                                  (v13/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "ConvertedNoteToIssueEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v59/*: any*/),
                            "type": "DisconnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v51/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "canonical",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v13/*: any*/),
                                      (v21/*: any*/),
                                      (v60/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v21/*: any*/),
                                      (v13/*: any*/),
                                      (v60/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v16/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v61/*: any*/),
                              (v18/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUndo",
                                "storageKey": null
                              },
                              (v13/*: any*/),
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
                              (v51/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "canonical",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v62/*: any*/),
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v62/*: any*/),
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v16/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v61/*: any*/),
                              (v18/*: any*/)
                            ],
                            "type": "UnmarkedAsDuplicateEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v18/*: any*/),
                              (v51/*: any*/),
                              (v23/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Discussion",
                                "kind": "LinkedField",
                                "name": "discussion",
                                "plural": false,
                                "selections": [
                                  (v22/*: any*/),
                                  (v21/*: any*/),
                                  (v13/*: any*/)
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
                              (v23/*: any*/),
                              (v51/*: any*/),
                              (v50/*: any*/),
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
                              (v23/*: any*/),
                              (v51/*: any*/),
                              (v18/*: any*/)
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
                      },
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
                  (v17/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v14/*: any*/),
                "filters": [],
                "handle": "connection",
                "key": "timelineBackwards_timelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              (v22/*: any*/),
              (v37/*: any*/)
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
    "id": "cb5836c08f541cda116f5087d899cc1f",
    "metadata": {},
    "name": "TimelinePaginationBackwardQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "7d2927017612819eb100b1a07551c08a";

export default node;
