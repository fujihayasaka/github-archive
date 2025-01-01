/**
 * @generated SignedSource<<886fa67f3dd7129bab806ee69ceb0678>>
 * @relayHash e687c8756b8df6e8a520a6c88282edb6
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID e687c8756b8df6e8a520a6c88282edb6

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTimelineItemTestQuery$variables = {
  id: string;
};
export type IssueTimelineItemTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineItem">;
  } | null | undefined;
};
export type IssueTimelineItemTestQuery = {
  response: IssueTimelineItemTestQuery$data;
  variables: IssueTimelineItemTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
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
  "name": "databaseId",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v6 = [
  (v5/*: any*/)
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileUrl",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "willCloseTarget",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v12 = [
  (v11/*: any*/)
],
v13 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": (v12/*: any*/),
    "storageKey": null
  }
],
v14 = {
  "kind": "InlineFragment",
  "selections": (v12/*: any*/),
  "type": "User",
  "abstractKey": null
},
v15 = {
  "kind": "InlineFragment",
  "selections": (v12/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v16 = {
  "kind": "InlineFragment",
  "selections": (v12/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v17 = {
  "kind": "InlineFragment",
  "selections": (v12/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v18 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": (v12/*: any*/),
    "storageKey": null
  }
],
v19 = {
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
v20 = [
  (v2/*: any*/),
  (v5/*: any*/),
  (v11/*: any*/)
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
  "name": "name",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCopilot",
  "storageKey": null
},
v27 = {
  "kind": "InlineFragment",
  "selections": (v12/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v28 = [
  (v2/*: any*/),
  (v27/*: any*/)
],
v29 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v12/*: any*/),
  "storageKey": null
},
v30 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v31 = {
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
v32 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v20/*: any*/),
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v11/*: any*/),
    (v23/*: any*/),
    (v24/*: any*/),
    (v32/*: any*/)
  ],
  "storageKey": null
},
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v11/*: any*/),
    (v30/*: any*/),
    (v22/*: any*/),
    (v21/*: any*/),
    (v31/*: any*/),
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
  "name": "state",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v39 = {
  "kind": "InlineFragment",
  "selections": [
    (v11/*: any*/),
    (v35/*: any*/),
    (v22/*: any*/),
    (v21/*: any*/),
    (v36/*: any*/),
    (v37/*: any*/),
    (v38/*: any*/),
    (v33/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v40 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v41 = {
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
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v43 = {
  "kind": "InlineFragment",
  "selections": [
    (v26/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v40/*: any*/),
    (v41/*: any*/),
    (v5/*: any*/),
    (v42/*: any*/),
    (v43/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v46 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v11/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v23/*: any*/),
      (v45/*: any*/),
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
  (v3/*: any*/),
  (v4/*: any*/),
  (v44/*: any*/)
],
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v48 = [
  (v5/*: any*/),
  (v47/*: any*/)
],
v49 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "assignee",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v14/*: any*/),
    (v15/*: any*/),
    (v16/*: any*/),
    (v17/*: any*/),
    (v27/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": [
        (v5/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v48/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v48/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v48/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v5/*: any*/),
            (v47/*: any*/),
            (v26/*: any*/)
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
v50 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v11/*: any*/),
      (v22/*: any*/)
    ],
    "storageKey": null
  },
  (v3/*: any*/),
  (v4/*: any*/),
  (v44/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v51 = [
  (v4/*: any*/),
  (v3/*: any*/),
  (v44/*: any*/)
],
v52 = {
  "kind": "InlineFragment",
  "selections": [
    (v34/*: any*/),
    (v39/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v54 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v23/*: any*/),
    (v32/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v55 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v56 = [
  (v3/*: any*/),
  (v4/*: any*/),
  (v44/*: any*/)
],
v57 = [
  (v3/*: any*/),
  (v44/*: any*/),
  (v4/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v11/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v30/*: any*/),
              (v22/*: any*/),
              (v21/*: any*/),
              (v31/*: any*/),
              (v33/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v35/*: any*/),
              (v22/*: any*/),
              (v21/*: any*/),
              (v36/*: any*/),
              (v37/*: any*/),
              (v38/*: any*/),
              (v33/*: any*/)
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
v58 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v23/*: any*/),
    (v24/*: any*/),
    (v32/*: any*/)
  ],
  "storageKey": null
},
v59 = [
  (v3/*: any*/),
  (v44/*: any*/),
  (v4/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v29/*: any*/),
      (v3/*: any*/),
      (v11/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v30/*: any*/),
              (v22/*: any*/),
              (v21/*: any*/),
              (v31/*: any*/),
              (v58/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v35/*: any*/),
              (v22/*: any*/),
              (v21/*: any*/),
              (v36/*: any*/),
              (v37/*: any*/),
              (v38/*: any*/),
              (v58/*: any*/)
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
v60 = [
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
v61 = [
  (v3/*: any*/),
  (v44/*: any*/),
  (v4/*: any*/),
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
          (v53/*: any*/),
          (v22/*: any*/),
          (v21/*: any*/),
          (v36/*: any*/),
          (v37/*: any*/),
          (v38/*: any*/),
          (v54/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v27/*: any*/)
    ],
    "storageKey": null
  }
],
v62 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v30/*: any*/),
        (v22/*: any*/),
        (v31/*: any*/),
        (v33/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v35/*: any*/),
        (v22/*: any*/),
        (v36/*: any*/),
        (v37/*: any*/),
        (v38/*: any*/),
        (v33/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v63 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v64 = [
  (v52/*: any*/)
],
v65 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v53/*: any*/),
    (v22/*: any*/),
    (v11/*: any*/)
  ],
  "storageKey": null
},
v66 = [
  (v23/*: any*/),
  (v45/*: any*/),
  (v11/*: any*/)
],
v67 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v66/*: any*/),
  "storageKey": null
},
v68 = [
  (v3/*: any*/),
  (v44/*: any*/),
  (v4/*: any*/),
  (v67/*: any*/)
],
v69 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
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
  "type": "Actor"
},
v72 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v73 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v74 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v75 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v76 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v77 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v78 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v79 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v80 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v81 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v82 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v83 = {
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
v84 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v85 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v86 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
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
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v90 = {
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
v91 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTimelineItemTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineDataFragmentSpread",
            "name": "IssueTimelineItem",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  (v2/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v3/*: any*/),
                      (v4/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "actor",
                        "plural": false,
                        "selections": (v6/*: any*/),
                        "storageKey": null
                      }
                    ],
                    "type": "TimelineEvent",
                    "abstractKey": "__isTimelineEvent"
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v3/*: any*/),
                      (v7/*: any*/),
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
                            "selections": (v6/*: any*/),
                            "storageKey": null
                          }
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
                          (v8/*: any*/),
                          (v9/*: any*/)
                        ],
                        "storageKey": null
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
                        "selections": [
                          (v2/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v10/*: any*/)
                    ],
                    "type": "CrossReferencedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v13/*: any*/),
                    "type": "LabeledEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v13/*: any*/),
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
                          (v14/*: any*/),
                          (v15/*: any*/),
                          (v16/*: any*/),
                          (v17/*: any*/)
                        ],
                        "storageKey": null
                      }
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
                          (v2/*: any*/),
                          (v14/*: any*/),
                          (v15/*: any*/),
                          (v16/*: any*/),
                          (v17/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "type": "UnassignedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v18/*: any*/),
                    "type": "MilestonedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v18/*: any*/),
                    "type": "DemilestonedEvent",
                    "abstractKey": null
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "IssueComment_issueComment"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "SubscribedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UnsubscribedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "MentionedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ClosedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ReopenedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "LockedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UnlockedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "PinnedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UnpinnedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "LabeledEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "RenamedTitleEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UnlabeledEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UnassignedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "AssignedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "CommentDeletedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UserBlockedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "SubIssueAddedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "SubIssueRemovedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ParentIssueAddedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ParentIssueRemovedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "MilestonedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "DemilestonedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "CrossReferencedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ReferencedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ConnectedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "TransferredEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "DisconnectedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "MarkedAsDuplicateEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "UnmarkedAsDuplicateEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ConvertedToDiscussionEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "AddedToProjectV2Event"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "RemovedFromProjectV2Event"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ProjectV2ItemStatusChangedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "ConvertedFromDraftEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "IssueTypeAddedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "IssueTypeRemovedEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "IssueTypeChangedEvent"
                  },
                  (v19/*: any*/)
                ],
                "type": "IssueTimelineItems",
                "abstractKey": "__isIssueTimelineItems"
              }
            ],
            "args": null,
            "argumentDefinitions": []
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssueTimelineItemTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v11/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "actor",
                    "plural": false,
                    "selections": (v20/*: any*/),
                    "storageKey": null
                  }
                ],
                "type": "TimelineEvent",
                "abstractKey": "__isTimelineEvent"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v7/*: any*/),
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
                      (v11/*: any*/),
                      (v21/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "locked",
                        "storageKey": null
                      },
                      (v3/*: any*/)
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
                      (v5/*: any*/),
                      (v8/*: any*/),
                      (v9/*: any*/),
                      (v11/*: any*/)
                    ],
                    "storageKey": null
                  },
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
                  (v4/*: any*/),
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
                      (v4/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isActive",
                        "storageKey": null
                      },
                      (v11/*: any*/)
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
                      (v11/*: any*/),
                      (v23/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "owner",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          (v11/*: any*/),
                          (v5/*: any*/),
                          (v22/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v24/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "slashCommandsEnabled",
                        "storageKey": null
                      },
                      (v25/*: any*/),
                      (v3/*: any*/)
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
                              (v22/*: any*/),
                              (v5/*: any*/),
                              (v11/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v11/*: any*/)
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
                                  (v2/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v6/*: any*/),
                                    "type": "User",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v5/*: any*/),
                                      (v26/*: any*/)
                                    ],
                                    "type": "Bot",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v6/*: any*/),
                                    "type": "Organization",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v6/*: any*/),
                                    "type": "Mannequin",
                                    "abstractKey": null
                                  },
                                  (v27/*: any*/)
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
                    "selections": (v28/*: any*/),
                    "storageKey": null
                  },
                  (v10/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "referencedAt",
                    "storageKey": null
                  },
                  (v3/*: any*/),
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
                          (v29/*: any*/)
                        ],
                        "type": "Issue",
                        "abstractKey": null
                      },
                      (v27/*: any*/)
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
                      (v34/*: any*/),
                      (v39/*: any*/),
                      (v27/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v44/*: any*/)
                ],
                "type": "CrossReferencedEvent",
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
                "selections": [
                  (v49/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v44/*: any*/)
                ],
                "type": "AssignedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v49/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "actor",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v5/*: any*/),
                      (v40/*: any*/),
                      (v41/*: any*/),
                      (v42/*: any*/),
                      (v43/*: any*/),
                      (v11/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "UnassignedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v50/*: any*/),
                "type": "MilestonedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v50/*: any*/),
                "type": "DemilestonedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
                "type": "SubscribedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
                "type": "UnsubscribedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
                "type": "MentionedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v31/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "duplicateOf",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v52/*: any*/),
                      (v27/*: any*/)
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
                          (v22/*: any*/),
                          (v53/*: any*/)
                        ],
                        "type": "ProjectV2",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v22/*: any*/),
                          (v21/*: any*/),
                          (v54/*: any*/)
                        ],
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v22/*: any*/),
                          (v55/*: any*/),
                          (v54/*: any*/)
                        ],
                        "type": "Commit",
                        "abstractKey": null
                      },
                      (v27/*: any*/)
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
                "selections": (v56/*: any*/),
                "type": "ReopenedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
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
                "selections": (v56/*: any*/),
                "type": "UnlockedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v56/*: any*/),
                "type": "PinnedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v56/*: any*/),
                "type": "UnpinnedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
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
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v44/*: any*/),
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
                  (v3/*: any*/),
                  (v4/*: any*/),
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
                      (v5/*: any*/),
                      (v11/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "UserBlockedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v57/*: any*/),
                "type": "SubIssueAddedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v57/*: any*/),
                "type": "SubIssueRemovedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v59/*: any*/),
                "type": "ParentIssueAddedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v59/*: any*/),
                "type": "ParentIssueRemovedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
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
                  (v44/*: any*/),
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
                      (v55/*: any*/),
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
                              (v5/*: any*/),
                              (v8/*: any*/),
                              (v11/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v36/*: any*/),
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
                                "selections": (v60/*: any*/),
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "CertificateAttributes",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": (v60/*: any*/),
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
                          (v23/*: any*/),
                          (v32/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "defaultBranch",
                            "storageKey": null
                          },
                          (v11/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v11/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v4/*: any*/)
                ],
                "type": "ReferencedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v61/*: any*/),
                "type": "ConnectedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v44/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "fromRepository",
                    "plural": false,
                    "selections": [
                      (v25/*: any*/),
                      (v22/*: any*/),
                      (v11/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "TransferredEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v61/*: any*/),
                "type": "DisconnectedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v44/*: any*/),
                  (v4/*: any*/),
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
                          (v11/*: any*/),
                          (v21/*: any*/),
                          (v62/*: any*/)
                        ],
                        "type": "Issue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v21/*: any*/),
                          (v11/*: any*/),
                          (v62/*: any*/)
                        ],
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      (v27/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v63/*: any*/),
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanUndo",
                    "storageKey": null
                  },
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
                  (v4/*: any*/),
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
                        "selections": (v64/*: any*/),
                        "type": "Issue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": (v64/*: any*/),
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      (v27/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v63/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "UnmarkedAsDuplicateEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v44/*: any*/),
                  (v4/*: any*/),
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
                      (v11/*: any*/)
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
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v44/*: any*/),
                  (v65/*: any*/)
                ],
                "type": "AddedToProjectV2Event",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v44/*: any*/),
                  (v65/*: any*/)
                ],
                "type": "RemovedFromProjectV2Event",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v44/*: any*/),
                  (v65/*: any*/),
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
                  (v4/*: any*/),
                  (v44/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "ConvertedFromDraftEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v68/*: any*/),
                "type": "IssueTypeAddedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v68/*: any*/),
                "type": "IssueTypeRemovedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v44/*: any*/),
                  (v4/*: any*/),
                  (v67/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "IssueType",
                    "kind": "LinkedField",
                    "name": "prevIssueType",
                    "plural": false,
                    "selections": (v66/*: any*/),
                    "storageKey": null
                  }
                ],
                "type": "IssueTypeChangedEvent",
                "abstractKey": null
              },
              (v19/*: any*/)
            ],
            "type": "IssueTimelineItems",
            "abstractKey": "__isIssueTimelineItems"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "e687c8756b8df6e8a520a6c88282edb6",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__id": (v69/*: any*/),
        "node.__isComment": (v70/*: any*/),
        "node.__isIssueTimelineItems": (v70/*: any*/),
        "node.__isReactable": (v70/*: any*/),
        "node.__isTimelineEvent": (v70/*: any*/),
        "node.__typename": (v70/*: any*/),
        "node.actor": (v71/*: any*/),
        "node.actor.__isActor": (v70/*: any*/),
        "node.actor.__typename": (v70/*: any*/),
        "node.actor.avatarUrl": (v72/*: any*/),
        "node.actor.id": (v69/*: any*/),
        "node.actor.isCopilot": (v73/*: any*/),
        "node.actor.login": (v70/*: any*/),
        "node.actor.profileResourcePath": (v74/*: any*/),
        "node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "node.assignee.__isActor": (v70/*: any*/),
        "node.assignee.__isNode": (v70/*: any*/),
        "node.assignee.__typename": (v70/*: any*/),
        "node.assignee.id": (v69/*: any*/),
        "node.assignee.isCopilot": (v73/*: any*/),
        "node.assignee.login": (v70/*: any*/),
        "node.assignee.resourcePath": (v72/*: any*/),
        "node.author": (v71/*: any*/),
        "node.author.__typename": (v70/*: any*/),
        "node.author.avatarUrl": (v72/*: any*/),
        "node.author.id": (v69/*: any*/),
        "node.author.login": (v70/*: any*/),
        "node.author.profileUrl": (v74/*: any*/),
        "node.authorAssociation": {
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
        "node.authorToRepoOwnerSponsorship": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Sponsorship"
        },
        "node.authorToRepoOwnerSponsorship.createdAt": (v75/*: any*/),
        "node.authorToRepoOwnerSponsorship.id": (v69/*: any*/),
        "node.authorToRepoOwnerSponsorship.isActive": (v73/*: any*/),
        "node.blockDuration": {
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
        "node.blockedUser": (v76/*: any*/),
        "node.blockedUser.id": (v69/*: any*/),
        "node.blockedUser.login": (v70/*: any*/),
        "node.body": (v70/*: any*/),
        "node.bodyHTML": (v77/*: any*/),
        "node.bodyVersion": (v70/*: any*/),
        "node.canonical": (v78/*: any*/),
        "node.canonical.__isNode": (v70/*: any*/),
        "node.canonical.__isReferencedSubject": (v70/*: any*/),
        "node.canonical.__typename": (v70/*: any*/),
        "node.canonical.id": (v69/*: any*/),
        "node.canonical.isDraft": (v73/*: any*/),
        "node.canonical.isInMergeQueue": (v73/*: any*/),
        "node.canonical.issueTitleHTML": (v70/*: any*/),
        "node.canonical.number": (v79/*: any*/),
        "node.canonical.pullTitleHTML": (v77/*: any*/),
        "node.canonical.repository": (v80/*: any*/),
        "node.canonical.repository.id": (v69/*: any*/),
        "node.canonical.repository.isPrivate": (v73/*: any*/),
        "node.canonical.repository.name": (v70/*: any*/),
        "node.canonical.repository.owner": (v81/*: any*/),
        "node.canonical.repository.owner.__typename": (v70/*: any*/),
        "node.canonical.repository.owner.id": (v69/*: any*/),
        "node.canonical.repository.owner.login": (v70/*: any*/),
        "node.canonical.state": (v82/*: any*/),
        "node.canonical.stateReason": (v83/*: any*/),
        "node.canonical.url": (v72/*: any*/),
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v70/*: any*/),
        "node.closer.__typename": (v70/*: any*/),
        "node.closer.abbreviatedOid": (v70/*: any*/),
        "node.closer.id": (v69/*: any*/),
        "node.closer.number": (v79/*: any*/),
        "node.closer.repository": (v80/*: any*/),
        "node.closer.repository.id": (v69/*: any*/),
        "node.closer.repository.name": (v70/*: any*/),
        "node.closer.repository.owner": (v81/*: any*/),
        "node.closer.repository.owner.__typename": (v70/*: any*/),
        "node.closer.repository.owner.id": (v69/*: any*/),
        "node.closer.repository.owner.login": (v70/*: any*/),
        "node.closer.title": (v70/*: any*/),
        "node.closer.url": (v72/*: any*/),
        "node.closingProjectItemStatus": (v84/*: any*/),
        "node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "node.commit.abbreviatedOid": (v70/*: any*/),
        "node.commit.hasSignature": (v73/*: any*/),
        "node.commit.id": (v69/*: any*/),
        "node.commit.message": (v70/*: any*/),
        "node.commit.messageBodyHTML": (v77/*: any*/),
        "node.commit.messageHeadlineHTML": (v77/*: any*/),
        "node.commit.repository": (v80/*: any*/),
        "node.commit.repository.defaultBranch": (v70/*: any*/),
        "node.commit.repository.id": (v69/*: any*/),
        "node.commit.repository.name": (v70/*: any*/),
        "node.commit.repository.owner": (v81/*: any*/),
        "node.commit.repository.owner.__typename": (v70/*: any*/),
        "node.commit.repository.owner.id": (v69/*: any*/),
        "node.commit.repository.owner.login": (v70/*: any*/),
        "node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "node.commit.signature.__typename": (v70/*: any*/),
        "node.commit.signature.issuer": (v85/*: any*/),
        "node.commit.signature.issuer.commonName": (v84/*: any*/),
        "node.commit.signature.issuer.emailAddress": (v84/*: any*/),
        "node.commit.signature.issuer.organization": (v84/*: any*/),
        "node.commit.signature.issuer.organizationUnit": (v84/*: any*/),
        "node.commit.signature.keyFingerprint": (v84/*: any*/),
        "node.commit.signature.keyId": (v84/*: any*/),
        "node.commit.signature.signer": (v76/*: any*/),
        "node.commit.signature.signer.avatarUrl": (v72/*: any*/),
        "node.commit.signature.signer.id": (v69/*: any*/),
        "node.commit.signature.signer.login": (v70/*: any*/),
        "node.commit.signature.state": {
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
        "node.commit.signature.subject": (v85/*: any*/),
        "node.commit.signature.subject.commonName": (v84/*: any*/),
        "node.commit.signature.subject.emailAddress": (v84/*: any*/),
        "node.commit.signature.subject.organization": (v84/*: any*/),
        "node.commit.signature.subject.organizationUnit": (v84/*: any*/),
        "node.commit.signature.wasSignedByGitHub": (v73/*: any*/),
        "node.commit.url": (v72/*: any*/),
        "node.commit.verificationStatus": {
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
        "node.createdAt": (v75/*: any*/),
        "node.createdViaEmail": (v73/*: any*/),
        "node.currentTitle": (v70/*: any*/),
        "node.databaseId": (v86/*: any*/),
        "node.deletedCommentAuthor": (v71/*: any*/),
        "node.deletedCommentAuthor.__typename": (v70/*: any*/),
        "node.deletedCommentAuthor.id": (v69/*: any*/),
        "node.deletedCommentAuthor.login": (v70/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v69/*: any*/),
        "node.discussion.number": (v79/*: any*/),
        "node.discussion.url": (v72/*: any*/),
        "node.duplicateOf": (v78/*: any*/),
        "node.duplicateOf.__isNode": (v70/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v70/*: any*/),
        "node.duplicateOf.__typename": (v70/*: any*/),
        "node.duplicateOf.id": (v69/*: any*/),
        "node.duplicateOf.isDraft": (v73/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v73/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v70/*: any*/),
        "node.duplicateOf.number": (v79/*: any*/),
        "node.duplicateOf.pullTitleHTML": (v77/*: any*/),
        "node.duplicateOf.repository": (v80/*: any*/),
        "node.duplicateOf.repository.id": (v69/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v73/*: any*/),
        "node.duplicateOf.repository.name": (v70/*: any*/),
        "node.duplicateOf.repository.owner": (v81/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v70/*: any*/),
        "node.duplicateOf.repository.owner.id": (v69/*: any*/),
        "node.duplicateOf.repository.owner.login": (v70/*: any*/),
        "node.duplicateOf.state": (v82/*: any*/),
        "node.duplicateOf.stateReason": (v83/*: any*/),
        "node.duplicateOf.url": (v72/*: any*/),
        "node.fromRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.fromRepository.id": (v69/*: any*/),
        "node.fromRepository.nameWithOwner": (v70/*: any*/),
        "node.fromRepository.url": (v72/*: any*/),
        "node.id": (v69/*: any*/),
        "node.innerSource": (v87/*: any*/),
        "node.innerSource.__isNode": (v70/*: any*/),
        "node.innerSource.__isReferencedSubject": (v70/*: any*/),
        "node.innerSource.__typename": (v70/*: any*/),
        "node.innerSource.id": (v69/*: any*/),
        "node.innerSource.isDraft": (v73/*: any*/),
        "node.innerSource.isInMergeQueue": (v73/*: any*/),
        "node.innerSource.issueTitleHTML": (v70/*: any*/),
        "node.innerSource.number": (v79/*: any*/),
        "node.innerSource.pullTitleHTML": (v77/*: any*/),
        "node.innerSource.repository": (v80/*: any*/),
        "node.innerSource.repository.id": (v69/*: any*/),
        "node.innerSource.repository.isPrivate": (v73/*: any*/),
        "node.innerSource.repository.name": (v70/*: any*/),
        "node.innerSource.repository.owner": (v81/*: any*/),
        "node.innerSource.repository.owner.__typename": (v70/*: any*/),
        "node.innerSource.repository.owner.id": (v69/*: any*/),
        "node.innerSource.repository.owner.login": (v70/*: any*/),
        "node.innerSource.state": (v82/*: any*/),
        "node.innerSource.stateReason": (v83/*: any*/),
        "node.innerSource.url": (v72/*: any*/),
        "node.isCanonicalOfClosedDuplicate": (v88/*: any*/),
        "node.isHidden": (v73/*: any*/),
        "node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "node.issue.author": (v71/*: any*/),
        "node.issue.author.__typename": (v70/*: any*/),
        "node.issue.author.id": (v69/*: any*/),
        "node.issue.author.login": (v70/*: any*/),
        "node.issue.databaseId": (v86/*: any*/),
        "node.issue.id": (v69/*: any*/),
        "node.issue.locked": (v73/*: any*/),
        "node.issue.number": (v79/*: any*/),
        "node.issueType": (v89/*: any*/),
        "node.issueType.color": (v90/*: any*/),
        "node.issueType.id": (v69/*: any*/),
        "node.issueType.name": (v70/*: any*/),
        "node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "node.label.color": (v70/*: any*/),
        "node.label.description": (v84/*: any*/),
        "node.label.id": (v69/*: any*/),
        "node.label.name": (v70/*: any*/),
        "node.label.nameHTML": (v70/*: any*/),
        "node.lastEditedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "node.lastUserContentEdit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "UserContentEdit"
        },
        "node.lastUserContentEdit.editor": (v71/*: any*/),
        "node.lastUserContentEdit.editor.__typename": (v70/*: any*/),
        "node.lastUserContentEdit.editor.id": (v69/*: any*/),
        "node.lastUserContentEdit.editor.login": (v70/*: any*/),
        "node.lastUserContentEdit.editor.url": (v72/*: any*/),
        "node.lastUserContentEdit.id": (v69/*: any*/),
        "node.lockReason": {
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
        "node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestone.id": (v69/*: any*/),
        "node.milestone.url": (v72/*: any*/),
        "node.milestoneTitle": (v70/*: any*/),
        "node.minimizedReason": (v84/*: any*/),
        "node.parent": (v91/*: any*/),
        "node.parent.__isReferencedSubject": (v70/*: any*/),
        "node.parent.__typename": (v70/*: any*/),
        "node.parent.databaseId": (v86/*: any*/),
        "node.parent.id": (v69/*: any*/),
        "node.parent.isDraft": (v73/*: any*/),
        "node.parent.isInMergeQueue": (v73/*: any*/),
        "node.parent.issueTitleHTML": (v70/*: any*/),
        "node.parent.number": (v79/*: any*/),
        "node.parent.pullTitleHTML": (v77/*: any*/),
        "node.parent.repository": (v80/*: any*/),
        "node.parent.repository.id": (v69/*: any*/),
        "node.parent.repository.isPrivate": (v73/*: any*/),
        "node.parent.repository.name": (v70/*: any*/),
        "node.parent.repository.owner": (v81/*: any*/),
        "node.parent.repository.owner.__typename": (v70/*: any*/),
        "node.parent.repository.owner.id": (v69/*: any*/),
        "node.parent.repository.owner.login": (v70/*: any*/),
        "node.parent.state": (v82/*: any*/),
        "node.parent.stateReason": (v83/*: any*/),
        "node.parent.url": (v72/*: any*/),
        "node.pendingBlock": (v88/*: any*/),
        "node.pendingMinimizeReason": (v84/*: any*/),
        "node.pendingUnblock": (v88/*: any*/),
        "node.pendingUndo": (v88/*: any*/),
        "node.prevIssueType": (v89/*: any*/),
        "node.prevIssueType.color": (v90/*: any*/),
        "node.prevIssueType.id": (v69/*: any*/),
        "node.prevIssueType.name": (v70/*: any*/),
        "node.previousStatus": (v70/*: any*/),
        "node.previousTitle": (v70/*: any*/),
        "node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.project.id": (v69/*: any*/),
        "node.project.title": (v70/*: any*/),
        "node.project.url": (v72/*: any*/),
        "node.reactionGroups": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ReactionGroup"
        },
        "node.reactionGroups.content": {
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
        "node.reactionGroups.reactors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ReactorConnection"
        },
        "node.reactionGroups.reactors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Reactor"
        },
        "node.reactionGroups.reactors.nodes.__isNode": (v70/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v70/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v69/*: any*/),
        "node.reactionGroups.reactors.nodes.isCopilot": (v73/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v70/*: any*/),
        "node.reactionGroups.reactors.totalCount": (v79/*: any*/),
        "node.reactionGroups.viewerHasReacted": (v73/*: any*/),
        "node.referencedAt": (v75/*: any*/),
        "node.repository": (v80/*: any*/),
        "node.repository.databaseId": (v86/*: any*/),
        "node.repository.id": (v69/*: any*/),
        "node.repository.isPrivate": (v73/*: any*/),
        "node.repository.name": (v70/*: any*/),
        "node.repository.nameWithOwner": (v70/*: any*/),
        "node.repository.owner": (v81/*: any*/),
        "node.repository.owner.__typename": (v70/*: any*/),
        "node.repository.owner.id": (v69/*: any*/),
        "node.repository.owner.login": (v70/*: any*/),
        "node.repository.owner.url": (v72/*: any*/),
        "node.repository.slashCommandsEnabled": (v73/*: any*/),
        "node.showSpammyBadge": (v73/*: any*/),
        "node.source": (v87/*: any*/),
        "node.source.__isNode": (v70/*: any*/),
        "node.source.__typename": (v70/*: any*/),
        "node.source.id": (v69/*: any*/),
        "node.stateReason": (v83/*: any*/),
        "node.status": (v70/*: any*/),
        "node.subIssue": (v91/*: any*/),
        "node.subIssue.__isReferencedSubject": (v70/*: any*/),
        "node.subIssue.__typename": (v70/*: any*/),
        "node.subIssue.databaseId": (v86/*: any*/),
        "node.subIssue.id": (v69/*: any*/),
        "node.subIssue.isDraft": (v73/*: any*/),
        "node.subIssue.isInMergeQueue": (v73/*: any*/),
        "node.subIssue.issueTitleHTML": (v70/*: any*/),
        "node.subIssue.number": (v79/*: any*/),
        "node.subIssue.pullTitleHTML": (v77/*: any*/),
        "node.subIssue.repository": (v80/*: any*/),
        "node.subIssue.repository.id": (v69/*: any*/),
        "node.subIssue.repository.isPrivate": (v73/*: any*/),
        "node.subIssue.repository.name": (v70/*: any*/),
        "node.subIssue.repository.owner": (v81/*: any*/),
        "node.subIssue.repository.owner.__typename": (v70/*: any*/),
        "node.subIssue.repository.owner.id": (v69/*: any*/),
        "node.subIssue.repository.owner.login": (v70/*: any*/),
        "node.subIssue.state": (v82/*: any*/),
        "node.subIssue.stateReason": (v83/*: any*/),
        "node.subIssue.url": (v72/*: any*/),
        "node.subject": (v87/*: any*/),
        "node.subject.__isNode": (v70/*: any*/),
        "node.subject.__typename": (v70/*: any*/),
        "node.subject.id": (v69/*: any*/),
        "node.subject.isDraft": (v73/*: any*/),
        "node.subject.isInMergeQueue": (v73/*: any*/),
        "node.subject.number": (v79/*: any*/),
        "node.subject.repository": (v80/*: any*/),
        "node.subject.repository.id": (v69/*: any*/),
        "node.subject.repository.name": (v70/*: any*/),
        "node.subject.repository.owner": (v81/*: any*/),
        "node.subject.repository.owner.__typename": (v70/*: any*/),
        "node.subject.repository.owner.id": (v69/*: any*/),
        "node.subject.repository.owner.login": (v70/*: any*/),
        "node.subject.state": (v82/*: any*/),
        "node.subject.title": (v70/*: any*/),
        "node.subject.url": (v72/*: any*/),
        "node.target": (v87/*: any*/),
        "node.target.__isNode": (v70/*: any*/),
        "node.target.__typename": (v70/*: any*/),
        "node.target.id": (v69/*: any*/),
        "node.target.repository": (v80/*: any*/),
        "node.target.repository.id": (v69/*: any*/),
        "node.url": (v72/*: any*/),
        "node.viewerCanBlockFromOrg": (v73/*: any*/),
        "node.viewerCanDelete": (v73/*: any*/),
        "node.viewerCanMinimize": (v73/*: any*/),
        "node.viewerCanReadUserContentEdits": (v73/*: any*/),
        "node.viewerCanReport": (v73/*: any*/),
        "node.viewerCanReportToMaintainer": (v73/*: any*/),
        "node.viewerCanUnblockFromOrg": (v73/*: any*/),
        "node.viewerCanUndo": (v73/*: any*/),
        "node.viewerCanUpdate": (v73/*: any*/),
        "node.viewerDidAuthor": (v73/*: any*/),
        "node.willCloseSubject": (v73/*: any*/),
        "node.willCloseTarget": (v73/*: any*/)
      }
    },
    "name": "IssueTimelineItemTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "ceaf8011c124b1a9b160eeb772f0c668";

export default node;
