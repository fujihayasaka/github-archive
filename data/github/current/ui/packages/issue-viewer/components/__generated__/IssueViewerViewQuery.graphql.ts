/**
 * @generated SignedSource<<bda5c789e91cbda916428985d8bb8217>>
 * @relayHash 9d3a6d16ad0c46a03d480b34acb48982
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9d3a6d16ad0c46a03d480b34acb48982

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerViewQuery$variables = {
  allowedOwner?: string | null | undefined;
  number: number;
  owner: string;
  repo: string;
  useNewTimeline: boolean;
};
export type IssueViewerViewQuery$data = {
  readonly repository: {
    readonly isOwnerEnterpriseManaged: boolean | null | undefined;
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueViewerIssue">;
    };
  } | null | undefined;
  readonly safeViewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
  } | null | undefined;
};
export type IssueViewerViewQuery = {
  response: IssueViewerViewQuery$data;
  variables: IssueViewerViewQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "allowedOwner"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "useNewTimeline"
},
v5 = [
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
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOwnerEnterpriseManaged",
  "storageKey": null
},
v7 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v8 = {
  "kind": "Variable",
  "name": "allowedOwner",
  "variableName": "allowedOwner"
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v11 = [
  (v10/*: any*/)
],
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v21 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v22 = [
  (v9/*: any*/)
],
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v28 = {
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
v29 = [
  (v15/*: any*/),
  (v16/*: any*/),
  (v9/*: any*/)
],
v30 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v29/*: any*/),
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v14/*: any*/),
    (v30/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
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
  "name": "body",
  "storageKey": null
},
v37 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v39 = {
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
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
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
  "name": "createdAt",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v44 = [
  (v16/*: any*/)
],
v45 = {
  "kind": "InlineFragment",
  "selections": (v22/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v46 = {
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
            (v10/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v15/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v44/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v44/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v44/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v44/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v45/*: any*/)
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
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingBlock",
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v49 = [
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
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v52 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v52/*: any*/),
    (v53/*: any*/)
  ],
  "storageKey": null
},
v55 = [
  (v8/*: any*/),
  (v21/*: any*/)
],
v56 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v57 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v58 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v59 = {
  "alias": null,
  "args": (v55/*: any*/),
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
            (v9/*: any*/),
            (v12/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v9/*: any*/),
                (v23/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v56/*: any*/),
                (v17/*: any*/),
                {
                  "alias": null,
                  "args": (v57/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v15/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v9/*: any*/),
                        (v14/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v9/*: any*/),
                            (v58/*: any*/),
                            (v14/*: any*/),
                            (v50/*: any*/),
                            (v25/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v26/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v45/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v40/*: any*/),
                (v24/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v15/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v57/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v15/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v9/*: any*/),
                    (v58/*: any*/),
                    (v14/*: any*/),
                    (v50/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v45/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v15/*: any*/)
          ],
          "storageKey": null
        },
        (v51/*: any*/)
      ],
      "storageKey": null
    },
    (v54/*: any*/)
  ],
  "storageKey": null
},
v60 = {
  "alias": null,
  "args": (v55/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v61 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v62 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v61/*: any*/)
],
v63 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v53/*: any*/),
    (v52/*: any*/)
  ],
  "storageKey": null
},
v64 = {
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
v65 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
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
          "selections": (v29/*: any*/),
          "storageKey": null
        },
        (v9/*: any*/),
        (v24/*: any*/),
        (v34/*: any*/),
        (v19/*: any*/)
      ],
      "storageKey": null
    },
    (v9/*: any*/),
    (v36/*: any*/),
    {
      "alias": null,
      "args": [
        (v37/*: any*/)
      ],
      "kind": "ScalarField",
      "name": "bodyHTML",
      "storageKey": "bodyHTML(unfurlReferences:true)"
    },
    (v38/*: any*/),
    (v56/*: any*/),
    (v17/*: any*/),
    (v42/*: any*/),
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
        (v42/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isActive",
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
        (v15/*: any*/),
        (v9/*: any*/),
        (v16/*: any*/),
        (v43/*: any*/)
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
        (v9/*: any*/),
        (v14/*: any*/),
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "owner",
          "plural": false,
          "selections": [
            (v15/*: any*/),
            (v9/*: any*/),
            (v16/*: any*/),
            (v17/*: any*/)
          ],
          "storageKey": null
        },
        (v18/*: any*/),
        (v20/*: any*/),
        (v13/*: any*/),
        (v19/*: any*/)
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
                (v15/*: any*/),
                (v17/*: any*/),
                (v16/*: any*/),
                (v9/*: any*/)
              ],
              "storageKey": null
            },
            (v9/*: any*/)
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
        (v47/*: any*/),
        (v48/*: any*/)
      ]
    },
    (v46/*: any*/)
  ],
  "type": "IssueComment",
  "abstractKey": null
},
v66 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    (v16/*: any*/),
    (v9/*: any*/),
    (v35/*: any*/),
    (v39/*: any*/)
  ],
  "storageKey": null
},
v67 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "willCloseSubject",
  "storageKey": null
},
v68 = [
  (v15/*: any*/),
  (v45/*: any*/)
],
v69 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "subject",
  "plural": false,
  "selections": (v68/*: any*/),
  "storageKey": null
},
v70 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v71 = [
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
v72 = {
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
    (v17/*: any*/),
    (v70/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "signature",
      "plural": false,
      "selections": [
        (v15/*: any*/),
        {
          "alias": null,
          "args": null,
          "concreteType": "User",
          "kind": "LinkedField",
          "name": "signer",
          "plural": false,
          "selections": [
            (v16/*: any*/),
            (v43/*: any*/),
            (v9/*: any*/)
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
              "selections": (v71/*: any*/),
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": "CertificateAttributes",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": (v71/*: any*/),
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
        (v14/*: any*/),
        (v30/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "defaultBranch",
          "storageKey": null
        },
        (v9/*: any*/)
      ],
      "storageKey": null
    },
    (v9/*: any*/)
  ],
  "storageKey": null
},
v73 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "source",
  "plural": false,
  "selections": (v68/*: any*/),
  "storageKey": null
},
v74 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "willCloseTarget",
  "storageKey": null
},
v75 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "referencedAt",
  "storageKey": null
},
v76 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "target",
  "plural": false,
  "selections": [
    (v15/*: any*/),
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
          "selections": (v22/*: any*/),
          "storageKey": null
        }
      ],
      "type": "Issue",
      "abstractKey": null
    },
    (v45/*: any*/)
  ],
  "storageKey": null
},
v77 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v78 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    (v14/*: any*/),
    (v18/*: any*/),
    (v30/*: any*/)
  ],
  "storageKey": null
},
v79 = {
  "kind": "InlineFragment",
  "selections": [
    (v9/*: any*/),
    (v77/*: any*/),
    (v17/*: any*/),
    (v24/*: any*/),
    (v28/*: any*/),
    (v78/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v80 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v81 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v82 = {
  "kind": "InlineFragment",
  "selections": [
    (v9/*: any*/),
    (v80/*: any*/),
    (v17/*: any*/),
    (v24/*: any*/),
    (v27/*: any*/),
    (v32/*: any*/),
    (v81/*: any*/),
    (v78/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v83 = {
  "alias": "innerSource",
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "source",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    {
      "kind": "TypeDiscriminator",
      "abstractKey": "__isReferencedSubject"
    },
    (v79/*: any*/),
    (v82/*: any*/),
    (v45/*: any*/)
  ],
  "storageKey": null
},
v84 = {
  "alias": null,
  "args": null,
  "concreteType": "Label",
  "kind": "LinkedField",
  "name": "label",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    (v50/*: any*/),
    (v14/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/)
  ],
  "storageKey": null
},
v85 = [
  (v42/*: any*/),
  (v66/*: any*/),
  (v84/*: any*/),
  (v19/*: any*/)
],
v86 = [
  (v9/*: any*/),
  (v16/*: any*/)
],
v87 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "assignee",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": (v86/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v86/*: any*/),
      "type": "Bot",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v86/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v86/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    (v45/*: any*/)
  ],
  "storageKey": null
},
v88 = [
  (v42/*: any*/),
  (v66/*: any*/),
  (v87/*: any*/),
  (v19/*: any*/)
],
v89 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v23/*: any*/),
    (v17/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v90 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    (v35/*: any*/),
    (v39/*: any*/),
    (v16/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v91 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v14/*: any*/),
    (v17/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v92 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v93 = {
  "kind": "InlineFragment",
  "selections": [
    (v42/*: any*/),
    (v90/*: any*/),
    (v91/*: any*/),
    (v92/*: any*/),
    (v19/*: any*/)
  ],
  "type": "AddedToProjectEvent",
  "abstractKey": null
},
v94 = {
  "kind": "InlineFragment",
  "selections": [
    (v42/*: any*/),
    (v19/*: any*/),
    (v90/*: any*/),
    (v91/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "previousProjectColumnName",
      "storageKey": null
    },
    (v92/*: any*/)
  ],
  "type": "MovedColumnsInProjectEvent",
  "abstractKey": null
},
v95 = {
  "kind": "InlineFragment",
  "selections": [
    (v42/*: any*/),
    (v19/*: any*/),
    (v90/*: any*/),
    (v91/*: any*/),
    (v92/*: any*/)
  ],
  "type": "RemovedFromProjectEvent",
  "abstractKey": null
},
v96 = [
  (v42/*: any*/),
  (v19/*: any*/),
  (v90/*: any*/)
],
v97 = {
  "kind": "InlineFragment",
  "selections": (v96/*: any*/),
  "type": "SubscribedEvent",
  "abstractKey": null
},
v98 = {
  "kind": "InlineFragment",
  "selections": (v96/*: any*/),
  "type": "UnsubscribedEvent",
  "abstractKey": null
},
v99 = {
  "kind": "InlineFragment",
  "selections": [
    (v79/*: any*/),
    (v82/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v100 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v42/*: any*/),
    (v28/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "duplicateOf",
      "plural": false,
      "selections": [
        (v15/*: any*/),
        (v99/*: any*/),
        (v45/*: any*/)
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
        (v15/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v17/*: any*/),
            (v23/*: any*/)
          ],
          "type": "ProjectV2",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v17/*: any*/),
            (v24/*: any*/),
            (v31/*: any*/)
          ],
          "type": "PullRequest",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v17/*: any*/),
            (v70/*: any*/),
            (v31/*: any*/)
          ],
          "type": "Commit",
          "abstractKey": null
        },
        (v45/*: any*/)
      ],
      "storageKey": null
    },
    (v90/*: any*/)
  ],
  "type": "ClosedEvent",
  "abstractKey": null
},
v101 = [
  (v19/*: any*/),
  (v42/*: any*/),
  (v90/*: any*/)
],
v102 = {
  "kind": "InlineFragment",
  "selections": (v101/*: any*/),
  "type": "ReopenedEvent",
  "abstractKey": null
},
v103 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "lockReason",
      "storageKey": null
    },
    (v90/*: any*/)
  ],
  "type": "LockedEvent",
  "abstractKey": null
},
v104 = {
  "kind": "InlineFragment",
  "selections": (v101/*: any*/),
  "type": "UnlockedEvent",
  "abstractKey": null
},
v105 = {
  "kind": "InlineFragment",
  "selections": (v101/*: any*/),
  "type": "PinnedEvent",
  "abstractKey": null
},
v106 = {
  "kind": "InlineFragment",
  "selections": (v101/*: any*/),
  "type": "UnpinnedEvent",
  "abstractKey": null
},
v107 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v42/*: any*/),
    (v90/*: any*/),
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
v108 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v42/*: any*/),
    (v90/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "deletedCommentAuthor",
      "plural": false,
      "selections": (v29/*: any*/),
      "storageKey": null
    }
  ],
  "type": "CommentDeletedEvent",
  "abstractKey": null
},
v109 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "blockDuration",
      "storageKey": null
    },
    (v90/*: any*/),
    {
      "alias": "blockedUser",
      "args": null,
      "concreteType": "User",
      "kind": "LinkedField",
      "name": "subject",
      "plural": false,
      "selections": [
        (v16/*: any*/),
        (v9/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "UserBlockedEvent",
  "abstractKey": null
},
v110 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "milestoneTitle",
  "storageKey": null
},
v111 = [
  (v19/*: any*/),
  (v42/*: any*/),
  (v90/*: any*/),
  (v110/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v17/*: any*/),
      (v9/*: any*/)
    ],
    "storageKey": null
  }
],
v112 = [
  (v19/*: any*/),
  (v90/*: any*/),
  (v42/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v15/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v23/*: any*/),
          (v17/*: any*/),
          (v24/*: any*/),
          (v27/*: any*/),
          (v32/*: any*/),
          (v81/*: any*/),
          (v31/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v45/*: any*/)
    ],
    "storageKey": null
  }
],
v113 = {
  "kind": "InlineFragment",
  "selections": (v112/*: any*/),
  "type": "ConnectedEvent",
  "abstractKey": null
},
v114 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v90/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "fromRepository",
      "plural": false,
      "selections": [
        (v13/*: any*/),
        (v17/*: any*/),
        (v9/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "TransferredEvent",
  "abstractKey": null
},
v115 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v90/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Project",
      "kind": "LinkedField",
      "name": "project",
      "plural": false,
      "selections": [
        (v17/*: any*/),
        (v14/*: any*/),
        (v9/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "ConvertedNoteToIssueEvent",
  "abstractKey": null
},
v116 = {
  "kind": "InlineFragment",
  "selections": (v112/*: any*/),
  "type": "DisconnectedEvent",
  "abstractKey": null
},
v117 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v77/*: any*/),
        (v17/*: any*/),
        (v28/*: any*/),
        (v78/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v80/*: any*/),
        (v17/*: any*/),
        (v27/*: any*/),
        (v32/*: any*/),
        (v81/*: any*/),
        (v78/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v118 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v119 = {
  "kind": "InlineFragment",
  "selections": [
    (v90/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "canonical",
      "plural": false,
      "selections": [
        (v15/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v9/*: any*/),
            (v24/*: any*/),
            (v117/*: any*/)
          ],
          "type": "Issue",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v24/*: any*/),
            (v9/*: any*/),
            (v117/*: any*/)
          ],
          "type": "PullRequest",
          "abstractKey": null
        },
        (v45/*: any*/)
      ],
      "storageKey": null
    },
    (v118/*: any*/),
    (v19/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanUndo",
      "storageKey": null
    },
    (v9/*: any*/),
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
v120 = [
  (v99/*: any*/)
],
v121 = {
  "kind": "InlineFragment",
  "selections": [
    (v90/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "canonical",
      "plural": false,
      "selections": [
        (v15/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v120/*: any*/),
          "type": "Issue",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v120/*: any*/),
          "type": "PullRequest",
          "abstractKey": null
        },
        (v45/*: any*/)
      ],
      "storageKey": null
    },
    (v118/*: any*/),
    (v19/*: any*/)
  ],
  "type": "UnmarkedAsDuplicateEvent",
  "abstractKey": null
},
v122 = {
  "kind": "InlineFragment",
  "selections": [
    (v19/*: any*/),
    (v90/*: any*/),
    (v42/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Discussion",
      "kind": "LinkedField",
      "name": "discussion",
      "plural": false,
      "selections": [
        (v17/*: any*/),
        (v24/*: any*/),
        (v9/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "ConvertedToDiscussionEvent",
  "abstractKey": null
},
v123 = {
  "kind": "InlineFragment",
  "selections": [
    (v42/*: any*/),
    (v90/*: any*/),
    (v89/*: any*/),
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
v124 = {
  "kind": "InlineFragment",
  "selections": [
    (v42/*: any*/),
    (v90/*: any*/),
    (v19/*: any*/)
  ],
  "type": "ConvertedFromDraftEvent",
  "abstractKey": null
},
v125 = {
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
        (v15/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/)
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        (v45/*: any*/),
        (v64/*: any*/),
        (v65/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v66/*: any*/),
            (v19/*: any*/),
            (v67/*: any*/),
            (v69/*: any*/),
            (v72/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v66/*: any*/),
            (v73/*: any*/),
            (v74/*: any*/),
            (v75/*: any*/),
            (v19/*: any*/),
            (v76/*: any*/),
            (v83/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v66/*: any*/),
            (v42/*: any*/),
            (v19/*: any*/)
          ],
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v85/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v85/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v88/*: any*/),
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v88/*: any*/),
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v66/*: any*/),
            (v19/*: any*/),
            (v89/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v66/*: any*/),
            (v89/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        (v93/*: any*/),
        (v94/*: any*/),
        (v95/*: any*/),
        (v97/*: any*/),
        (v98/*: any*/),
        (v100/*: any*/),
        (v102/*: any*/),
        (v103/*: any*/),
        (v104/*: any*/),
        (v105/*: any*/),
        (v106/*: any*/),
        (v107/*: any*/),
        (v108/*: any*/),
        (v109/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v111/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v111/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        (v113/*: any*/),
        (v114/*: any*/),
        (v115/*: any*/),
        (v116/*: any*/),
        (v119/*: any*/),
        (v121/*: any*/),
        (v122/*: any*/),
        (v123/*: any*/),
        (v124/*: any*/)
      ],
      "storageKey": null
    },
    (v51/*: any*/)
  ],
  "storageKey": null
},
v126 = [
  "visibleEventsOnly"
],
v127 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v61/*: any*/)
],
v128 = {
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
v129 = [
  (v84/*: any*/),
  (v19/*: any*/),
  (v42/*: any*/),
  (v90/*: any*/)
],
v130 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v9/*: any*/),
      (v17/*: any*/)
    ],
    "storageKey": null
  },
  (v19/*: any*/),
  (v42/*: any*/),
  (v90/*: any*/),
  (v110/*: any*/)
],
v131 = {
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
        (v15/*: any*/),
        {
          "kind": "TypeDiscriminator",
          "abstractKey": "__isIssueTimelineItems"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": (v29/*: any*/),
              "storageKey": null
            }
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        (v65/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v73/*: any*/),
            (v74/*: any*/),
            (v75/*: any*/),
            (v19/*: any*/),
            (v76/*: any*/),
            (v83/*: any*/),
            (v90/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v129/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v129/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v87/*: any*/),
            (v19/*: any*/),
            (v42/*: any*/),
            (v90/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v87/*: any*/),
            (v19/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": [
                (v15/*: any*/),
                (v16/*: any*/),
                (v35/*: any*/),
                (v39/*: any*/),
                (v9/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v130/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v130/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        (v93/*: any*/),
        (v94/*: any*/),
        (v95/*: any*/),
        (v97/*: any*/),
        (v98/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v96/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        (v100/*: any*/),
        (v102/*: any*/),
        (v103/*: any*/),
        (v104/*: any*/),
        (v105/*: any*/),
        (v106/*: any*/),
        (v107/*: any*/),
        (v108/*: any*/),
        (v109/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v67/*: any*/),
            (v69/*: any*/),
            (v90/*: any*/),
            (v72/*: any*/),
            (v42/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        (v113/*: any*/),
        (v114/*: any*/),
        (v115/*: any*/),
        (v116/*: any*/),
        (v119/*: any*/),
        (v121/*: any*/),
        (v122/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": [
            (v19/*: any*/),
            (v42/*: any*/),
            (v90/*: any*/),
            (v89/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v42/*: any*/),
            (v90/*: any*/),
            (v89/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        (v123/*: any*/),
        (v124/*: any*/),
        (v64/*: any*/),
        (v45/*: any*/)
      ],
      "storageKey": null
    },
    (v51/*: any*/)
  ],
  "storageKey": null
},
v132 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 15
  },
  (v61/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueViewerViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v6/*: any*/),
          {
            "kind": "RequiredField",
            "field": {
              "alias": null,
              "args": (v7/*: any*/),
              "concreteType": "Issue",
              "kind": "LinkedField",
              "name": "issue",
              "plural": false,
              "selections": [
                {
                  "args": [
                    (v8/*: any*/),
                    {
                      "kind": "Variable",
                      "name": "useNewTimeline",
                      "variableName": "useNewTimeline"
                    }
                  ],
                  "kind": "FragmentSpread",
                  "name": "IssueViewerIssue"
                }
              ],
              "storageKey": null
            },
            "action": "THROW",
            "path": "repository.issue"
          }
        ],
        "storageKey": null
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
    "argumentDefinitions": [
      (v3/*: any*/),
      (v2/*: any*/),
      (v1/*: any*/),
      (v0/*: any*/),
      (v4/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueViewerViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v6/*: any*/),
          {
            "alias": null,
            "args": (v7/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v9/*: any*/),
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
                "selections": (v11/*: any*/),
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
                  (v12/*: any*/),
                  (v9/*: any*/),
                  (v13/*: any*/),
                  (v14/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v15/*: any*/),
                      (v16/*: any*/),
                      (v9/*: any*/),
                      (v17/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v18/*: any*/),
                  (v19/*: any*/),
                  (v20/*: any*/),
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
                    "selections": (v11/*: any*/),
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
                    "args": [
                      (v21/*: any*/)
                    ],
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
                            "selections": (v22/*: any*/),
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
              (v23/*: any*/),
              (v24/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "titleHTML",
                "storageKey": null
              },
              (v17/*: any*/),
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
                  (v14/*: any*/),
                  (v25/*: any*/),
                  (v9/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isEnabled",
                    "storageKey": null
                  },
                  (v26/*: any*/)
                ],
                "storageKey": null
              },
              (v27/*: any*/),
              (v28/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v24/*: any*/),
                  (v17/*: any*/),
                  (v31/*: any*/),
                  (v9/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v21/*: any*/),
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
                          (v13/*: any*/),
                          (v9/*: any*/),
                          (v14/*: any*/),
                          (v30/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v27/*: any*/),
                      (v32/*: any*/),
                      (v17/*: any*/),
                      (v24/*: any*/),
                      (v9/*: any*/)
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
              (v19/*: any*/),
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
                  (v15/*: any*/),
                  (v35/*: any*/),
                  (v16/*: any*/),
                  (v9/*: any*/)
                ],
                "storageKey": null
              },
              (v36/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v37/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v38/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": (v22/*: any*/),
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
                      (v9/*: any*/),
                      (v16/*: any*/),
                      (v14/*: any*/),
                      (v39/*: any*/)
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
                  (v9/*: any*/),
                  (v23/*: any*/),
                  (v40/*: any*/),
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
                  (v17/*: any*/),
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
                      (v40/*: any*/),
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "subIssues(first:50)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v42/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "author",
                    "plural": false,
                    "selections": [
                      (v43/*: any*/),
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
              (v46/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v47/*: any*/),
                  (v48/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v49/*: any*/),
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
                              (v9/*: any*/),
                              (v25/*: any*/),
                              (v14/*: any*/),
                              (v50/*: any*/),
                              (v26/*: any*/),
                              (v17/*: any*/),
                              (v15/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v51/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v54/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v49/*: any*/),
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
                      (v59/*: any*/),
                      (v60/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v59/*: any*/),
                      (v60/*: any*/),
                      (v56/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              },
              {
                "condition": "useNewTimeline",
                "kind": "Condition",
                "passingValue": false,
                "selections": [
                  {
                    "alias": "frontTimeline",
                    "args": (v62/*: any*/),
                    "concreteType": "IssueTimelineItemsConnection",
                    "kind": "LinkedField",
                    "name": "timelineItems",
                    "plural": false,
                    "selections": [
                      (v10/*: any*/),
                      (v63/*: any*/),
                      (v125/*: any*/),
                      (v64/*: any*/)
                    ],
                    "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
                  },
                  {
                    "alias": "frontTimeline",
                    "args": (v62/*: any*/),
                    "filters": (v126/*: any*/),
                    "handle": "connection",
                    "key": "Issue_frontTimeline",
                    "kind": "LinkedHandle",
                    "name": "timelineItems"
                  },
                  {
                    "alias": null,
                    "args": (v127/*: any*/),
                    "concreteType": "IssueTimelineItemsConnection",
                    "kind": "LinkedField",
                    "name": "timelineItems",
                    "plural": false,
                    "selections": [
                      (v10/*: any*/),
                      (v128/*: any*/),
                      (v125/*: any*/),
                      (v64/*: any*/)
                    ],
                    "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
                  },
                  {
                    "alias": null,
                    "args": (v127/*: any*/),
                    "filters": (v126/*: any*/),
                    "handle": "connection",
                    "key": "IssueBacksideTimeline_timelineItems",
                    "kind": "LinkedHandle",
                    "name": "timelineItems"
                  }
                ]
              },
              {
                "condition": "useNewTimeline",
                "kind": "Condition",
                "passingValue": true,
                "selections": [
                  {
                    "alias": "frontTimelineItems",
                    "args": (v62/*: any*/),
                    "concreteType": "IssueTimelineItemsConnection",
                    "kind": "LinkedField",
                    "name": "timelineItems",
                    "plural": false,
                    "selections": [
                      (v63/*: any*/),
                      (v10/*: any*/),
                      (v131/*: any*/)
                    ],
                    "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
                  },
                  {
                    "alias": "frontTimelineItems",
                    "args": (v62/*: any*/),
                    "filters": (v126/*: any*/),
                    "handle": "connection",
                    "key": "Issue__frontTimelineItems",
                    "kind": "LinkedHandle",
                    "name": "timelineItems"
                  },
                  {
                    "alias": "backTimelineItems",
                    "args": (v132/*: any*/),
                    "concreteType": "IssueTimelineItemsConnection",
                    "kind": "LinkedField",
                    "name": "timelineItems",
                    "plural": false,
                    "selections": [
                      (v128/*: any*/),
                      (v10/*: any*/),
                      (v131/*: any*/)
                    ],
                    "storageKey": "timelineItems(last:15,visibleEventsOnly:true)"
                  },
                  {
                    "alias": "backTimelineItems",
                    "args": (v132/*: any*/),
                    "filters": (v126/*: any*/),
                    "handle": "connection",
                    "key": "Issue__backTimelineItems",
                    "kind": "LinkedHandle",
                    "name": "timelineItems"
                  }
                ]
              }
            ],
            "storageKey": null
          },
          (v9/*: any*/)
        ],
        "storageKey": null
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
          (v16/*: any*/),
          (v9/*: any*/),
          (v39/*: any*/),
          (v14/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isEmployee",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "9d3a6d16ad0c46a03d480b34acb48982",
    "metadata": {},
    "name": "IssueViewerViewQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "04922d05444f1d769373e6a47a0eb6b1";

export default node;
