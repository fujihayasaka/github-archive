/**
 * @generated SignedSource<<8929ff38990332505c31713659f52b6b>>
 * @relayHash 47363436fe7c145b371a60f1044d91df
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 47363436fe7c145b371a60f1044d91df

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerViewQuery$variables = {
  allowedOwner?: string | null | undefined;
  number: number;
  owner: string;
  repo: string;
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
v4 = [
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
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOwnerEnterpriseManaged",
  "storageKey": null
},
v6 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v7 = {
  "kind": "Variable",
  "name": "allowedOwner",
  "variableName": "allowedOwner"
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
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
  "name": "isArchived",
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
  "name": "databaseId",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v21 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v22 = [
  (v8/*: any*/)
],
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v26 = {
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
v27 = [
  (v13/*: any*/),
  (v14/*: any*/),
  (v8/*: any*/)
],
v28 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v27/*: any*/),
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v28/*: any*/),
    (v8/*: any*/)
  ],
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
  "name": "profileResourcePath",
  "storageKey": null
},
v32 = {
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
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCopilot",
  "storageKey": null
},
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v33/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v35 = {
  "kind": "InlineFragment",
  "selections": (v22/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "locked",
  "storageKey": null
},
v39 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileUrl",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v43 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
},
v47 = {
  "kind": "Literal",
  "name": "visibleEventsOnly",
  "value": true
},
v48 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 15
  },
  (v47/*: any*/)
],
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "endCursor",
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v52 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingBlock",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "pendingUnblock",
  "storageKey": null
},
v55 = [
  (v14/*: any*/)
],
v56 = {
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
            (v20/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v55/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v14/*: any*/),
                    (v33/*: any*/)
                  ],
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v55/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v55/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v35/*: any*/)
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
v57 = [
  (v13/*: any*/),
  (v35/*: any*/)
],
v58 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v22/*: any*/),
  "storageKey": null
},
v59 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v60 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v12/*: any*/),
    (v17/*: any*/),
    (v28/*: any*/)
  ],
  "storageKey": null
},
v61 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v59/*: any*/),
    (v15/*: any*/),
    (v10/*: any*/),
    (v26/*: any*/),
    (v60/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v62 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v63 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v64 = {
  "kind": "InlineFragment",
  "selections": [
    (v8/*: any*/),
    (v62/*: any*/),
    (v15/*: any*/),
    (v10/*: any*/),
    (v25/*: any*/),
    (v30/*: any*/),
    (v63/*: any*/),
    (v60/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v65 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    (v39/*: any*/),
    (v32/*: any*/),
    (v14/*: any*/),
    (v31/*: any*/),
    (v34/*: any*/),
    (v8/*: any*/)
  ],
  "storageKey": null
},
v66 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v67 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v8/*: any*/),
      (v66/*: any*/),
      (v12/*: any*/),
      (v23/*: any*/),
      (v24/*: any*/)
    ],
    "storageKey": null
  },
  (v18/*: any*/),
  (v51/*: any*/),
  (v65/*: any*/)
],
v68 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v69 = [
  (v14/*: any*/),
  (v68/*: any*/)
],
v70 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "assignee",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": (v22/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v22/*: any*/),
      "type": "Bot",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v22/*: any*/),
      "type": "Mannequin",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v22/*: any*/),
      "type": "Organization",
      "abstractKey": null
    },
    (v35/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": [
        (v14/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v69/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v14/*: any*/),
            (v68/*: any*/),
            (v33/*: any*/)
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
v71 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v8/*: any*/),
      (v15/*: any*/)
    ],
    "storageKey": null
  },
  (v18/*: any*/),
  (v51/*: any*/),
  (v65/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v72 = [
  (v51/*: any*/),
  (v18/*: any*/),
  (v65/*: any*/)
],
v73 = {
  "kind": "InlineFragment",
  "selections": [
    (v61/*: any*/),
    (v64/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v74 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v75 = [
  (v18/*: any*/),
  (v51/*: any*/),
  (v65/*: any*/)
],
v76 = [
  (v18/*: any*/),
  (v65/*: any*/),
  (v51/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v18/*: any*/),
      (v8/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v13/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v59/*: any*/),
              (v15/*: any*/),
              (v10/*: any*/),
              (v26/*: any*/),
              (v60/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v62/*: any*/),
              (v15/*: any*/),
              (v10/*: any*/),
              (v25/*: any*/),
              (v30/*: any*/),
              (v63/*: any*/),
              (v60/*: any*/)
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
v77 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v17/*: any*/),
    (v28/*: any*/)
  ],
  "storageKey": null
},
v78 = [
  (v18/*: any*/),
  (v65/*: any*/),
  (v51/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v58/*: any*/),
      (v18/*: any*/),
      (v8/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v13/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v59/*: any*/),
              (v15/*: any*/),
              (v10/*: any*/),
              (v26/*: any*/),
              (v77/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v62/*: any*/),
              (v15/*: any*/),
              (v10/*: any*/),
              (v25/*: any*/),
              (v30/*: any*/),
              (v63/*: any*/),
              (v77/*: any*/)
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
v79 = [
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
v80 = [
  (v18/*: any*/),
  (v65/*: any*/),
  (v51/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v13/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v9/*: any*/),
          (v15/*: any*/),
          (v10/*: any*/),
          (v25/*: any*/),
          (v30/*: any*/),
          (v63/*: any*/),
          (v29/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v35/*: any*/)
    ],
    "storageKey": null
  }
],
v81 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v59/*: any*/),
        (v15/*: any*/),
        (v26/*: any*/),
        (v60/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v62/*: any*/),
        (v15/*: any*/),
        (v25/*: any*/),
        (v30/*: any*/),
        (v63/*: any*/),
        (v60/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v82 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v83 = [
  (v73/*: any*/)
],
v84 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    (v15/*: any*/),
    (v8/*: any*/)
  ],
  "storageKey": null
},
v85 = [
  (v12/*: any*/),
  (v23/*: any*/),
  (v8/*: any*/)
],
v86 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v85/*: any*/),
  "storageKey": null
},
v87 = [
  (v18/*: any*/),
  (v65/*: any*/),
  (v51/*: any*/),
  (v86/*: any*/)
],
v88 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v89 = {
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
        (v13/*: any*/),
        {
          "kind": "TypeDiscriminator",
          "abstractKey": "__isIssueTimelineItems"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": (v27/*: any*/),
              "storageKey": null
            }
          ],
          "type": "TimelineEvent",
          "abstractKey": "__isTimelineEvent"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v37/*: any*/),
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
                  "selections": (v27/*: any*/),
                  "storageKey": null
                },
                (v8/*: any*/),
                (v10/*: any*/),
                (v38/*: any*/),
                (v18/*: any*/)
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
                (v13/*: any*/),
                (v14/*: any*/),
                (v41/*: any*/),
                (v40/*: any*/),
                (v8/*: any*/)
              ],
              "storageKey": null
            },
            (v8/*: any*/),
            (v42/*: any*/),
            {
              "alias": null,
              "args": [
                (v43/*: any*/)
              ],
              "kind": "ScalarField",
              "name": "bodyHTML",
              "storageKey": "bodyHTML(unfurlReferences:true)"
            },
            (v44/*: any*/),
            (v52/*: any*/),
            (v15/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "authorAssociation",
              "storageKey": null
            },
            (v45/*: any*/),
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
                (v51/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "isActive",
                  "storageKey": null
                },
                (v8/*: any*/)
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
                (v8/*: any*/),
                (v12/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "owner",
                  "plural": false,
                  "selections": [
                    (v13/*: any*/),
                    (v8/*: any*/),
                    (v14/*: any*/),
                    (v15/*: any*/)
                  ],
                  "storageKey": null
                },
                (v17/*: any*/),
                (v19/*: any*/),
                (v11/*: any*/),
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
                        (v13/*: any*/),
                        (v15/*: any*/),
                        (v14/*: any*/),
                        (v8/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v8/*: any*/)
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
                (v53/*: any*/),
                (v54/*: any*/)
              ]
            },
            (v56/*: any*/)
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
              "selections": (v57/*: any*/),
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
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v58/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                (v35/*: any*/)
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
                (v13/*: any*/),
                {
                  "kind": "TypeDiscriminator",
                  "abstractKey": "__isReferencedSubject"
                },
                (v61/*: any*/),
                (v64/*: any*/),
                (v35/*: any*/)
              ],
              "storageKey": null
            },
            (v65/*: any*/)
          ],
          "type": "CrossReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "LabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v67/*: any*/),
          "type": "UnlabeledEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v70/*: any*/),
            (v18/*: any*/),
            (v51/*: any*/),
            (v65/*: any*/)
          ],
          "type": "AssignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v70/*: any*/),
            (v18/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "actor",
              "plural": false,
              "selections": [
                (v13/*: any*/),
                (v14/*: any*/),
                (v39/*: any*/),
                (v32/*: any*/),
                (v31/*: any*/),
                (v34/*: any*/),
                (v8/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UnassignedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "MilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v71/*: any*/),
          "type": "DemilestonedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v72/*: any*/),
          "type": "SubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v72/*: any*/),
          "type": "UnsubscribedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v72/*: any*/),
          "type": "MentionedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v51/*: any*/),
            (v26/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "duplicateOf",
              "plural": false,
              "selections": [
                (v13/*: any*/),
                (v73/*: any*/),
                (v35/*: any*/)
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
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v15/*: any*/),
                    (v9/*: any*/)
                  ],
                  "type": "ProjectV2",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v15/*: any*/),
                    (v10/*: any*/),
                    (v29/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v15/*: any*/),
                    (v74/*: any*/),
                    (v29/*: any*/)
                  ],
                  "type": "Commit",
                  "abstractKey": null
                },
                (v35/*: any*/)
              ],
              "storageKey": null
            },
            (v65/*: any*/)
          ],
          "type": "ClosedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v75/*: any*/),
          "type": "ReopenedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "lockReason",
              "storageKey": null
            },
            (v65/*: any*/)
          ],
          "type": "LockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v75/*: any*/),
          "type": "UnlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v75/*: any*/),
          "type": "PinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v75/*: any*/),
          "type": "UnpinnedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v51/*: any*/),
            (v65/*: any*/),
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
            (v51/*: any*/),
            (v65/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "deletedCommentAuthor",
              "plural": false,
              "selections": (v27/*: any*/),
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
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "blockDuration",
              "storageKey": null
            },
            (v65/*: any*/),
            {
              "alias": "blockedUser",
              "args": null,
              "concreteType": "User",
              "kind": "LinkedField",
              "name": "subject",
              "plural": false,
              "selections": [
                (v14/*: any*/),
                (v8/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "UserBlockedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v76/*: any*/),
          "type": "SubIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v76/*: any*/),
          "type": "SubIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v78/*: any*/),
          "type": "ParentIssueAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v78/*: any*/),
          "type": "ParentIssueRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
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
              "selections": (v57/*: any*/),
              "storageKey": null
            },
            (v65/*: any*/),
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
                (v74/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "signature",
                  "plural": false,
                  "selections": [
                    (v13/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "User",
                      "kind": "LinkedField",
                      "name": "signer",
                      "plural": false,
                      "selections": [
                        (v14/*: any*/),
                        (v41/*: any*/),
                        (v8/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v25/*: any*/),
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
                          "selections": (v79/*: any*/),
                          "storageKey": null
                        },
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "CertificateAttributes",
                          "kind": "LinkedField",
                          "name": "subject",
                          "plural": false,
                          "selections": (v79/*: any*/),
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
                    (v12/*: any*/),
                    (v28/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "defaultBranch",
                      "storageKey": null
                    },
                    (v8/*: any*/)
                  ],
                  "storageKey": null
                },
                (v8/*: any*/)
              ],
              "storageKey": null
            },
            (v51/*: any*/)
          ],
          "type": "ReferencedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v80/*: any*/),
          "type": "ConnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v65/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Repository",
              "kind": "LinkedField",
              "name": "fromRepository",
              "plural": false,
              "selections": [
                (v11/*: any*/),
                (v15/*: any*/),
                (v8/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "type": "TransferredEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v80/*: any*/),
          "type": "DisconnectedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v65/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v8/*: any*/),
                    (v10/*: any*/),
                    (v81/*: any*/)
                  ],
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v10/*: any*/),
                    (v8/*: any*/),
                    (v81/*: any*/)
                  ],
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v35/*: any*/)
              ],
              "storageKey": null
            },
            (v82/*: any*/),
            (v18/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "viewerCanUndo",
              "storageKey": null
            },
            (v8/*: any*/),
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
            (v65/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "canonical",
              "plural": false,
              "selections": [
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v83/*: any*/),
                  "type": "Issue",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v83/*: any*/),
                  "type": "PullRequest",
                  "abstractKey": null
                },
                (v35/*: any*/)
              ],
              "storageKey": null
            },
            (v82/*: any*/),
            (v18/*: any*/)
          ],
          "type": "UnmarkedAsDuplicateEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v65/*: any*/),
            (v51/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Discussion",
              "kind": "LinkedField",
              "name": "discussion",
              "plural": false,
              "selections": [
                (v15/*: any*/),
                (v10/*: any*/),
                (v8/*: any*/)
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
            (v18/*: any*/),
            (v51/*: any*/),
            (v65/*: any*/),
            (v84/*: any*/)
          ],
          "type": "AddedToProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v51/*: any*/),
            (v65/*: any*/),
            (v84/*: any*/)
          ],
          "type": "RemovedFromProjectV2Event",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v51/*: any*/),
            (v65/*: any*/),
            (v84/*: any*/),
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
            (v51/*: any*/),
            (v65/*: any*/),
            (v18/*: any*/)
          ],
          "type": "ConvertedFromDraftEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v87/*: any*/),
          "type": "IssueTypeAddedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v87/*: any*/),
          "type": "IssueTypeRemovedEvent",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v18/*: any*/),
            (v65/*: any*/),
            (v51/*: any*/),
            (v86/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueType",
              "kind": "LinkedField",
              "name": "prevIssueType",
              "plural": false,
              "selections": (v85/*: any*/),
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
        (v35/*: any*/)
      ],
      "storageKey": null
    },
    (v88/*: any*/)
  ],
  "storageKey": null
},
v90 = [
  "visibleEventsOnly"
],
v91 = [
  {
    "kind": "Literal",
    "name": "last",
    "value": 0
  },
  (v47/*: any*/)
],
v92 = [
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
v93 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    (v50/*: any*/),
    (v49/*: any*/)
  ],
  "storageKey": null
},
v94 = [
  (v7/*: any*/),
  (v21/*: any*/)
],
v95 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v96 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v97 = {
  "alias": null,
  "args": (v94/*: any*/),
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
            (v8/*: any*/),
            (v16/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v8/*: any*/),
                (v9/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v52/*: any*/),
                (v15/*: any*/),
                {
                  "alias": null,
                  "args": (v95/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v13/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v8/*: any*/),
                        (v12/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v8/*: any*/),
                            (v96/*: any*/),
                            (v12/*: any*/),
                            (v66/*: any*/),
                            (v23/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v24/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v35/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v36/*: any*/),
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v13/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v95/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v8/*: any*/),
                    (v96/*: any*/),
                    (v12/*: any*/),
                    (v66/*: any*/),
                    (v23/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v35/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v13/*: any*/)
          ],
          "storageKey": null
        },
        (v88/*: any*/)
      ],
      "storageKey": null
    },
    (v93/*: any*/)
  ],
  "storageKey": null
},
v98 = {
  "alias": null,
  "args": (v94/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueViewerViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v4/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v5/*: any*/),
          {
            "kind": "RequiredField",
            "field": {
              "alias": null,
              "args": (v6/*: any*/),
              "concreteType": "Issue",
              "kind": "LinkedField",
              "name": "issue",
              "plural": false,
              "selections": [
                {
                  "args": [
                    (v7/*: any*/)
                  ],
                  "kind": "FragmentSpread",
                  "name": "IssueViewerIssue"
                }
              ],
              "storageKey": null
            },
            "action": "THROW"
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
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueViewerViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v4/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v5/*: any*/),
          {
            "alias": null,
            "args": (v6/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v8/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "updatedAt",
                "storageKey": null
              },
              (v9/*: any*/),
              (v10/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v11/*: any*/),
                  (v8/*: any*/),
                  (v12/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v13/*: any*/),
                      (v14/*: any*/),
                      (v8/*: any*/),
                      (v15/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v16/*: any*/),
                  (v17/*: any*/),
                  (v18/*: any*/),
                  (v19/*: any*/),
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
                      (v20/*: any*/)
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
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "titleHTML",
                "storageKey": null
              },
              (v15/*: any*/),
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
                  (v12/*: any*/),
                  (v23/*: any*/),
                  (v8/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isEnabled",
                    "storageKey": null
                  },
                  (v24/*: any*/)
                ],
                "storageKey": null
              },
              (v25/*: any*/),
              (v26/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v10/*: any*/),
                  (v15/*: any*/),
                  (v29/*: any*/),
                  (v8/*: any*/)
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
                          (v11/*: any*/),
                          (v8/*: any*/),
                          (v12/*: any*/),
                          (v28/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v25/*: any*/),
                      (v30/*: any*/),
                      (v15/*: any*/),
                      (v10/*: any*/),
                      (v8/*: any*/)
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
                      (v13/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v8/*: any*/),
                          (v14/*: any*/),
                          (v12/*: any*/),
                          (v31/*: any*/),
                          (v32/*: any*/),
                          (v34/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      (v35/*: any*/)
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
                  (v8/*: any*/),
                  (v9/*: any*/),
                  (v36/*: any*/),
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
                  (v15/*: any*/),
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
              (v18/*: any*/),
              (v37/*: any*/),
              (v38/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v13/*: any*/),
                  (v39/*: any*/),
                  (v14/*: any*/),
                  (v8/*: any*/),
                  (v40/*: any*/),
                  (v41/*: any*/)
                ],
                "storageKey": null
              },
              (v42/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v43/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v44/*: any*/),
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
              (v45/*: any*/),
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
                      (v13/*: any*/),
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
                              (v13/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v8/*: any*/),
                                  (v12/*: any*/),
                                  (v46/*: any*/)
                                ],
                                "type": "IssueFieldText",
                                "abstractKey": null
                              },
                              (v35/*: any*/)
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
                              (v13/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v12/*: any*/),
                                  (v46/*: any*/)
                                ],
                                "type": "IssueFieldSingleSelect",
                                "abstractKey": null
                              },
                              (v35/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v12/*: any*/),
                          (v23/*: any*/),
                          (v24/*: any*/)
                        ],
                        "type": "IssueFieldSingleSelectValue",
                        "abstractKey": null
                      },
                      (v35/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "issueFieldValues(first:25)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v48/*: any*/),
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
                      (v49/*: any*/),
                      (v50/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v20/*: any*/),
                  (v89/*: any*/)
                ],
                "storageKey": "timelineItems(first:15,visibleEventsOnly:true)"
              },
              {
                "alias": "frontTimelineItems",
                "args": (v48/*: any*/),
                "filters": (v90/*: any*/),
                "handle": "connection",
                "key": "Issue__frontTimelineItems",
                "kind": "LinkedHandle",
                "name": "timelineItems"
              },
              {
                "alias": "backTimelineItems",
                "args": (v91/*: any*/),
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
                  (v20/*: any*/),
                  (v89/*: any*/)
                ],
                "storageKey": "timelineItems(last:0,visibleEventsOnly:true)"
              },
              {
                "alias": "backTimelineItems",
                "args": (v91/*: any*/),
                "filters": (v90/*: any*/),
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
                    "args": (v92/*: any*/),
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
                              (v8/*: any*/),
                              (v23/*: any*/),
                              (v12/*: any*/),
                              (v66/*: any*/),
                              (v24/*: any*/),
                              (v15/*: any*/),
                              (v13/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v88/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v93/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v92/*: any*/),
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
                  (v51/*: any*/)
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              },
              (v56/*: any*/),
              {
                "kind": "ClientExtension",
                "selections": [
                  (v53/*: any*/),
                  (v54/*: any*/)
                ]
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v97/*: any*/),
                      (v98/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v97/*: any*/),
                      (v98/*: any*/),
                      (v52/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              }
            ],
            "storageKey": null
          },
          (v8/*: any*/)
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
          (v14/*: any*/),
          (v8/*: any*/),
          (v32/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v13/*: any*/),
              (v12/*: any*/),
              (v31/*: any*/),
              (v34/*: any*/)
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
    "id": "47363436fe7c145b371a60f1044d91df",
    "metadata": {},
    "name": "IssueViewerViewQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "cafcab214103ad4fb85bdaf9d56dc1dd";

export default node;
