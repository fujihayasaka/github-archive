/**
 * @generated SignedSource<<2b120fa0eabb2de6742a241a99f8e205>>
 * @relayHash 287c360dc888e112250a2864ced910a9
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 287c360dc888e112250a2864ced910a9

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
  "name": "willCloseTarget",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v11 = [
  (v10/*: any*/)
],
v12 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": (v11/*: any*/),
    "storageKey": null
  }
],
v13 = {
  "kind": "InlineFragment",
  "selections": (v11/*: any*/),
  "type": "User",
  "abstractKey": null
},
v14 = {
  "kind": "InlineFragment",
  "selections": (v11/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v15 = {
  "kind": "InlineFragment",
  "selections": (v11/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v16 = {
  "kind": "InlineFragment",
  "selections": (v11/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v17 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": (v11/*: any*/),
    "storageKey": null
  }
],
v18 = {
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
v19 = [
  (v2/*: any*/),
  (v5/*: any*/),
  (v10/*: any*/)
],
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v25 = {
  "kind": "InlineFragment",
  "selections": (v11/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v26 = [
  (v2/*: any*/),
  (v25/*: any*/)
],
v27 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v11/*: any*/),
  "storageKey": null
},
v28 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v29 = {
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
v30 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v19/*: any*/),
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
    (v10/*: any*/),
    (v22/*: any*/),
    (v23/*: any*/),
    (v30/*: any*/)
  ],
  "storageKey": null
},
v32 = {
  "kind": "InlineFragment",
  "selections": [
    (v10/*: any*/),
    (v28/*: any*/),
    (v21/*: any*/),
    (v20/*: any*/),
    (v29/*: any*/),
    (v31/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v33 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v37 = {
  "kind": "InlineFragment",
  "selections": [
    (v10/*: any*/),
    (v33/*: any*/),
    (v21/*: any*/),
    (v20/*: any*/),
    (v34/*: any*/),
    (v35/*: any*/),
    (v36/*: any*/),
    (v31/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v38 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
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
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v38/*: any*/),
    (v39/*: any*/),
    (v5/*: any*/),
    (v10/*: any*/)
  ],
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v42 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v10/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v22/*: any*/),
      (v41/*: any*/),
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
  (v40/*: any*/)
],
v43 = [
  (v10/*: any*/),
  (v5/*: any*/)
],
v44 = {
  "kind": "InlineFragment",
  "selections": (v43/*: any*/),
  "type": "User",
  "abstractKey": null
},
v45 = {
  "kind": "InlineFragment",
  "selections": (v43/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v46 = {
  "kind": "InlineFragment",
  "selections": (v43/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v47 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v10/*: any*/),
      (v21/*: any*/)
    ],
    "storageKey": null
  },
  (v3/*: any*/),
  (v4/*: any*/),
  (v40/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v48 = [
  (v4/*: any*/),
  (v3/*: any*/),
  (v40/*: any*/)
],
v49 = {
  "kind": "InlineFragment",
  "selections": [
    (v32/*: any*/),
    (v37/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v22/*: any*/),
    (v30/*: any*/),
    (v10/*: any*/)
  ],
  "storageKey": null
},
v52 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v53 = [
  (v3/*: any*/),
  (v4/*: any*/),
  (v40/*: any*/)
],
v54 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v22/*: any*/),
    (v23/*: any*/),
    (v30/*: any*/)
  ],
  "storageKey": null
},
v55 = [
  (v27/*: any*/),
  (v3/*: any*/),
  (v10/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v28/*: any*/),
          (v21/*: any*/),
          (v20/*: any*/),
          (v29/*: any*/),
          (v54/*: any*/)
        ],
        "type": "Issue",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": [
          (v33/*: any*/),
          (v21/*: any*/),
          (v20/*: any*/),
          (v34/*: any*/),
          (v35/*: any*/),
          (v36/*: any*/),
          (v54/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      }
    ],
    "type": "ReferencedSubject",
    "abstractKey": "__isReferencedSubject"
  }
],
v56 = [
  (v3/*: any*/),
  (v40/*: any*/),
  (v4/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": (v55/*: any*/),
    "storageKey": null
  }
],
v57 = [
  (v3/*: any*/),
  (v40/*: any*/),
  (v4/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": (v55/*: any*/),
    "storageKey": null
  }
],
v58 = [
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
v59 = [
  (v3/*: any*/),
  (v40/*: any*/),
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
          (v50/*: any*/),
          (v21/*: any*/),
          (v20/*: any*/),
          (v34/*: any*/),
          (v35/*: any*/),
          (v36/*: any*/),
          (v51/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v25/*: any*/)
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
        (v28/*: any*/),
        (v21/*: any*/),
        (v29/*: any*/),
        (v31/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v33/*: any*/),
        (v21/*: any*/),
        (v34/*: any*/),
        (v35/*: any*/),
        (v36/*: any*/),
        (v31/*: any*/)
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
  (v49/*: any*/)
],
v63 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v50/*: any*/),
    (v21/*: any*/),
    (v10/*: any*/)
  ],
  "storageKey": null
},
v64 = [
  (v22/*: any*/),
  (v41/*: any*/),
  (v10/*: any*/)
],
v65 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v64/*: any*/),
  "storageKey": null
},
v66 = [
  (v3/*: any*/),
  (v40/*: any*/),
  (v4/*: any*/),
  (v65/*: any*/)
],
v67 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v68 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v69 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v70 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v71 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v72 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v73 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v74 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v75 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v76 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v77 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v78 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v79 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v80 = {
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
v81 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v82 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v83 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v84 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v85 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v86 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v87 = {
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
v88 = {
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
                          (v8/*: any*/)
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
                      (v9/*: any*/)
                    ],
                    "type": "CrossReferencedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v12/*: any*/),
                    "type": "LabeledEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v12/*: any*/),
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
                          (v13/*: any*/),
                          (v14/*: any*/),
                          (v15/*: any*/),
                          (v16/*: any*/)
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
                          (v13/*: any*/),
                          (v14/*: any*/),
                          (v15/*: any*/),
                          (v16/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "type": "UnassignedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v17/*: any*/),
                    "type": "MilestonedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v17/*: any*/),
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
                  (v18/*: any*/)
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
          (v10/*: any*/),
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
                    "selections": (v19/*: any*/),
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
                        "selections": (v19/*: any*/),
                        "storageKey": null
                      },
                      (v10/*: any*/),
                      (v20/*: any*/),
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
                      (v10/*: any*/)
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
                  (v21/*: any*/),
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
                      (v10/*: any*/)
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
                      (v10/*: any*/),
                      (v22/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "owner",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          (v10/*: any*/),
                          (v5/*: any*/),
                          (v21/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v23/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "slashCommandsEnabled",
                        "storageKey": null
                      },
                      (v24/*: any*/),
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
                              (v21/*: any*/),
                              (v5/*: any*/),
                              (v10/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v10/*: any*/)
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
                                    "selections": (v6/*: any*/),
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
                                  (v25/*: any*/)
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
                    "selections": (v26/*: any*/),
                    "storageKey": null
                  },
                  (v9/*: any*/),
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
                          (v27/*: any*/)
                        ],
                        "type": "Issue",
                        "abstractKey": null
                      },
                      (v25/*: any*/)
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
                      (v32/*: any*/),
                      (v37/*: any*/),
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v40/*: any*/)
                ],
                "type": "CrossReferencedEvent",
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
                      (v44/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v10/*: any*/),
                          (v5/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isCopilot",
                            "storageKey": null
                          }
                        ],
                        "type": "Bot",
                        "abstractKey": null
                      },
                      (v45/*: any*/),
                      (v46/*: any*/),
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v40/*: any*/)
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
                      (v44/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": (v43/*: any*/),
                        "type": "Bot",
                        "abstractKey": null
                      },
                      (v45/*: any*/),
                      (v46/*: any*/),
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
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
                      (v38/*: any*/),
                      (v39/*: any*/),
                      (v10/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "UnassignedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v47/*: any*/),
                "type": "MilestonedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v47/*: any*/),
                "type": "DemilestonedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v48/*: any*/),
                "type": "SubscribedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v48/*: any*/),
                "type": "UnsubscribedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v48/*: any*/),
                "type": "MentionedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v29/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "duplicateOf",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v49/*: any*/),
                      (v25/*: any*/)
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
                          (v21/*: any*/),
                          (v50/*: any*/)
                        ],
                        "type": "ProjectV2",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v21/*: any*/),
                          (v20/*: any*/),
                          (v51/*: any*/)
                        ],
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v21/*: any*/),
                          (v52/*: any*/),
                          (v51/*: any*/)
                        ],
                        "type": "Commit",
                        "abstractKey": null
                      },
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v40/*: any*/)
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
                  (v3/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "lockReason",
                    "storageKey": null
                  },
                  (v40/*: any*/)
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
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v40/*: any*/),
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
                  (v40/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "deletedCommentAuthor",
                    "plural": false,
                    "selections": (v19/*: any*/),
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
                  (v40/*: any*/),
                  {
                    "alias": "blockedUser",
                    "args": null,
                    "concreteType": "User",
                    "kind": "LinkedField",
                    "name": "subject",
                    "plural": false,
                    "selections": [
                      (v5/*: any*/),
                      (v10/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "UserBlockedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v56/*: any*/),
                "type": "SubIssueAddedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v56/*: any*/),
                "type": "SubIssueRemovedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v57/*: any*/),
                "type": "ParentIssueAddedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v57/*: any*/),
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
                    "selections": (v26/*: any*/),
                    "storageKey": null
                  },
                  (v40/*: any*/),
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
                      (v21/*: any*/),
                      (v52/*: any*/),
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
                              (v10/*: any*/)
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
                                "selections": (v58/*: any*/),
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "CertificateAttributes",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": (v58/*: any*/),
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
                          (v22/*: any*/),
                          (v30/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "defaultBranch",
                            "storageKey": null
                          },
                          (v10/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v10/*: any*/)
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
                "selections": (v59/*: any*/),
                "type": "ConnectedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v40/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "fromRepository",
                    "plural": false,
                    "selections": [
                      (v24/*: any*/),
                      (v21/*: any*/),
                      (v10/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "TransferredEvent",
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
                  (v40/*: any*/),
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
                          (v10/*: any*/),
                          (v20/*: any*/),
                          (v60/*: any*/)
                        ],
                        "type": "Issue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v20/*: any*/),
                          (v10/*: any*/),
                          (v60/*: any*/)
                        ],
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v61/*: any*/),
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
                  (v40/*: any*/),
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
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v61/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "UnmarkedAsDuplicateEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v40/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Discussion",
                    "kind": "LinkedField",
                    "name": "discussion",
                    "plural": false,
                    "selections": [
                      (v21/*: any*/),
                      (v20/*: any*/),
                      (v10/*: any*/)
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
                  (v40/*: any*/),
                  (v63/*: any*/)
                ],
                "type": "AddedToProjectV2Event",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v40/*: any*/),
                  (v63/*: any*/)
                ],
                "type": "RemovedFromProjectV2Event",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v40/*: any*/),
                  (v63/*: any*/),
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
                  (v40/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "ConvertedFromDraftEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v66/*: any*/),
                "type": "IssueTypeAddedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v66/*: any*/),
                "type": "IssueTypeRemovedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v40/*: any*/),
                  (v4/*: any*/),
                  (v65/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "IssueType",
                    "kind": "LinkedField",
                    "name": "prevIssueType",
                    "plural": false,
                    "selections": (v64/*: any*/),
                    "storageKey": null
                  }
                ],
                "type": "IssueTypeChangedEvent",
                "abstractKey": null
              },
              (v18/*: any*/)
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
    "id": "287c360dc888e112250a2864ced910a9",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__id": (v67/*: any*/),
        "node.__isComment": (v68/*: any*/),
        "node.__isIssueTimelineItems": (v68/*: any*/),
        "node.__isReactable": (v68/*: any*/),
        "node.__isTimelineEvent": (v68/*: any*/),
        "node.__typename": (v68/*: any*/),
        "node.actor": (v69/*: any*/),
        "node.actor.__isActor": (v68/*: any*/),
        "node.actor.__typename": (v68/*: any*/),
        "node.actor.avatarUrl": (v70/*: any*/),
        "node.actor.id": (v67/*: any*/),
        "node.actor.login": (v68/*: any*/),
        "node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "node.assignee.__isNode": (v68/*: any*/),
        "node.assignee.__typename": (v68/*: any*/),
        "node.assignee.id": (v67/*: any*/),
        "node.assignee.isCopilot": (v71/*: any*/),
        "node.assignee.login": (v68/*: any*/),
        "node.author": (v69/*: any*/),
        "node.author.__typename": (v68/*: any*/),
        "node.author.avatarUrl": (v70/*: any*/),
        "node.author.id": (v67/*: any*/),
        "node.author.login": (v68/*: any*/),
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
        "node.authorToRepoOwnerSponsorship.createdAt": (v72/*: any*/),
        "node.authorToRepoOwnerSponsorship.id": (v67/*: any*/),
        "node.authorToRepoOwnerSponsorship.isActive": (v71/*: any*/),
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
        "node.blockedUser": (v73/*: any*/),
        "node.blockedUser.id": (v67/*: any*/),
        "node.blockedUser.login": (v68/*: any*/),
        "node.body": (v68/*: any*/),
        "node.bodyHTML": (v74/*: any*/),
        "node.bodyVersion": (v68/*: any*/),
        "node.canonical": (v75/*: any*/),
        "node.canonical.__isNode": (v68/*: any*/),
        "node.canonical.__isReferencedSubject": (v68/*: any*/),
        "node.canonical.__typename": (v68/*: any*/),
        "node.canonical.id": (v67/*: any*/),
        "node.canonical.isDraft": (v71/*: any*/),
        "node.canonical.isInMergeQueue": (v71/*: any*/),
        "node.canonical.issueTitleHTML": (v68/*: any*/),
        "node.canonical.number": (v76/*: any*/),
        "node.canonical.pullTitleHTML": (v74/*: any*/),
        "node.canonical.repository": (v77/*: any*/),
        "node.canonical.repository.id": (v67/*: any*/),
        "node.canonical.repository.isPrivate": (v71/*: any*/),
        "node.canonical.repository.name": (v68/*: any*/),
        "node.canonical.repository.owner": (v78/*: any*/),
        "node.canonical.repository.owner.__typename": (v68/*: any*/),
        "node.canonical.repository.owner.id": (v67/*: any*/),
        "node.canonical.repository.owner.login": (v68/*: any*/),
        "node.canonical.state": (v79/*: any*/),
        "node.canonical.stateReason": (v80/*: any*/),
        "node.canonical.url": (v70/*: any*/),
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v68/*: any*/),
        "node.closer.__typename": (v68/*: any*/),
        "node.closer.abbreviatedOid": (v68/*: any*/),
        "node.closer.id": (v67/*: any*/),
        "node.closer.number": (v76/*: any*/),
        "node.closer.repository": (v77/*: any*/),
        "node.closer.repository.id": (v67/*: any*/),
        "node.closer.repository.name": (v68/*: any*/),
        "node.closer.repository.owner": (v78/*: any*/),
        "node.closer.repository.owner.__typename": (v68/*: any*/),
        "node.closer.repository.owner.id": (v67/*: any*/),
        "node.closer.repository.owner.login": (v68/*: any*/),
        "node.closer.title": (v68/*: any*/),
        "node.closer.url": (v70/*: any*/),
        "node.closingProjectItemStatus": (v81/*: any*/),
        "node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "node.commit.abbreviatedOid": (v68/*: any*/),
        "node.commit.hasSignature": (v71/*: any*/),
        "node.commit.id": (v67/*: any*/),
        "node.commit.message": (v68/*: any*/),
        "node.commit.messageBodyHTML": (v74/*: any*/),
        "node.commit.messageHeadlineHTML": (v74/*: any*/),
        "node.commit.repository": (v77/*: any*/),
        "node.commit.repository.defaultBranch": (v68/*: any*/),
        "node.commit.repository.id": (v67/*: any*/),
        "node.commit.repository.name": (v68/*: any*/),
        "node.commit.repository.owner": (v78/*: any*/),
        "node.commit.repository.owner.__typename": (v68/*: any*/),
        "node.commit.repository.owner.id": (v67/*: any*/),
        "node.commit.repository.owner.login": (v68/*: any*/),
        "node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "node.commit.signature.__typename": (v68/*: any*/),
        "node.commit.signature.issuer": (v82/*: any*/),
        "node.commit.signature.issuer.commonName": (v81/*: any*/),
        "node.commit.signature.issuer.emailAddress": (v81/*: any*/),
        "node.commit.signature.issuer.organization": (v81/*: any*/),
        "node.commit.signature.issuer.organizationUnit": (v81/*: any*/),
        "node.commit.signature.keyFingerprint": (v81/*: any*/),
        "node.commit.signature.keyId": (v81/*: any*/),
        "node.commit.signature.signer": (v73/*: any*/),
        "node.commit.signature.signer.avatarUrl": (v70/*: any*/),
        "node.commit.signature.signer.id": (v67/*: any*/),
        "node.commit.signature.signer.login": (v68/*: any*/),
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
        "node.commit.signature.subject": (v82/*: any*/),
        "node.commit.signature.subject.commonName": (v81/*: any*/),
        "node.commit.signature.subject.emailAddress": (v81/*: any*/),
        "node.commit.signature.subject.organization": (v81/*: any*/),
        "node.commit.signature.subject.organizationUnit": (v81/*: any*/),
        "node.commit.signature.wasSignedByGitHub": (v71/*: any*/),
        "node.commit.url": (v70/*: any*/),
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
        "node.createdAt": (v72/*: any*/),
        "node.createdViaEmail": (v71/*: any*/),
        "node.currentTitle": (v68/*: any*/),
        "node.databaseId": (v83/*: any*/),
        "node.deletedCommentAuthor": (v69/*: any*/),
        "node.deletedCommentAuthor.__typename": (v68/*: any*/),
        "node.deletedCommentAuthor.id": (v67/*: any*/),
        "node.deletedCommentAuthor.login": (v68/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v67/*: any*/),
        "node.discussion.number": (v76/*: any*/),
        "node.discussion.url": (v70/*: any*/),
        "node.duplicateOf": (v75/*: any*/),
        "node.duplicateOf.__isNode": (v68/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v68/*: any*/),
        "node.duplicateOf.__typename": (v68/*: any*/),
        "node.duplicateOf.id": (v67/*: any*/),
        "node.duplicateOf.isDraft": (v71/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v71/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v68/*: any*/),
        "node.duplicateOf.number": (v76/*: any*/),
        "node.duplicateOf.pullTitleHTML": (v74/*: any*/),
        "node.duplicateOf.repository": (v77/*: any*/),
        "node.duplicateOf.repository.id": (v67/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v71/*: any*/),
        "node.duplicateOf.repository.name": (v68/*: any*/),
        "node.duplicateOf.repository.owner": (v78/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v68/*: any*/),
        "node.duplicateOf.repository.owner.id": (v67/*: any*/),
        "node.duplicateOf.repository.owner.login": (v68/*: any*/),
        "node.duplicateOf.state": (v79/*: any*/),
        "node.duplicateOf.stateReason": (v80/*: any*/),
        "node.duplicateOf.url": (v70/*: any*/),
        "node.fromRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.fromRepository.id": (v67/*: any*/),
        "node.fromRepository.nameWithOwner": (v68/*: any*/),
        "node.fromRepository.url": (v70/*: any*/),
        "node.id": (v67/*: any*/),
        "node.innerSource": (v84/*: any*/),
        "node.innerSource.__isNode": (v68/*: any*/),
        "node.innerSource.__isReferencedSubject": (v68/*: any*/),
        "node.innerSource.__typename": (v68/*: any*/),
        "node.innerSource.id": (v67/*: any*/),
        "node.innerSource.isDraft": (v71/*: any*/),
        "node.innerSource.isInMergeQueue": (v71/*: any*/),
        "node.innerSource.issueTitleHTML": (v68/*: any*/),
        "node.innerSource.number": (v76/*: any*/),
        "node.innerSource.pullTitleHTML": (v74/*: any*/),
        "node.innerSource.repository": (v77/*: any*/),
        "node.innerSource.repository.id": (v67/*: any*/),
        "node.innerSource.repository.isPrivate": (v71/*: any*/),
        "node.innerSource.repository.name": (v68/*: any*/),
        "node.innerSource.repository.owner": (v78/*: any*/),
        "node.innerSource.repository.owner.__typename": (v68/*: any*/),
        "node.innerSource.repository.owner.id": (v67/*: any*/),
        "node.innerSource.repository.owner.login": (v68/*: any*/),
        "node.innerSource.state": (v79/*: any*/),
        "node.innerSource.stateReason": (v80/*: any*/),
        "node.innerSource.url": (v70/*: any*/),
        "node.isCanonicalOfClosedDuplicate": (v85/*: any*/),
        "node.isHidden": (v71/*: any*/),
        "node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "node.issue.author": (v69/*: any*/),
        "node.issue.author.__typename": (v68/*: any*/),
        "node.issue.author.id": (v67/*: any*/),
        "node.issue.author.login": (v68/*: any*/),
        "node.issue.databaseId": (v83/*: any*/),
        "node.issue.id": (v67/*: any*/),
        "node.issue.locked": (v71/*: any*/),
        "node.issue.number": (v76/*: any*/),
        "node.issueType": (v86/*: any*/),
        "node.issueType.color": (v87/*: any*/),
        "node.issueType.id": (v67/*: any*/),
        "node.issueType.name": (v68/*: any*/),
        "node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "node.label.color": (v68/*: any*/),
        "node.label.description": (v81/*: any*/),
        "node.label.id": (v67/*: any*/),
        "node.label.name": (v68/*: any*/),
        "node.label.nameHTML": (v68/*: any*/),
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
        "node.lastUserContentEdit.editor": (v69/*: any*/),
        "node.lastUserContentEdit.editor.__typename": (v68/*: any*/),
        "node.lastUserContentEdit.editor.id": (v67/*: any*/),
        "node.lastUserContentEdit.editor.login": (v68/*: any*/),
        "node.lastUserContentEdit.editor.url": (v70/*: any*/),
        "node.lastUserContentEdit.id": (v67/*: any*/),
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
        "node.milestone.id": (v67/*: any*/),
        "node.milestone.url": (v70/*: any*/),
        "node.milestoneTitle": (v68/*: any*/),
        "node.minimizedReason": (v81/*: any*/),
        "node.parent": (v88/*: any*/),
        "node.parent.__isReferencedSubject": (v68/*: any*/),
        "node.parent.__typename": (v68/*: any*/),
        "node.parent.databaseId": (v83/*: any*/),
        "node.parent.id": (v67/*: any*/),
        "node.parent.isDraft": (v71/*: any*/),
        "node.parent.isInMergeQueue": (v71/*: any*/),
        "node.parent.issueTitleHTML": (v68/*: any*/),
        "node.parent.number": (v76/*: any*/),
        "node.parent.pullTitleHTML": (v74/*: any*/),
        "node.parent.repository": (v77/*: any*/),
        "node.parent.repository.id": (v67/*: any*/),
        "node.parent.repository.isPrivate": (v71/*: any*/),
        "node.parent.repository.name": (v68/*: any*/),
        "node.parent.repository.owner": (v78/*: any*/),
        "node.parent.repository.owner.__typename": (v68/*: any*/),
        "node.parent.repository.owner.id": (v67/*: any*/),
        "node.parent.repository.owner.login": (v68/*: any*/),
        "node.parent.state": (v79/*: any*/),
        "node.parent.stateReason": (v80/*: any*/),
        "node.parent.url": (v70/*: any*/),
        "node.pendingBlock": (v85/*: any*/),
        "node.pendingMinimizeReason": (v81/*: any*/),
        "node.pendingUnblock": (v85/*: any*/),
        "node.pendingUndo": (v85/*: any*/),
        "node.prevIssueType": (v86/*: any*/),
        "node.prevIssueType.color": (v87/*: any*/),
        "node.prevIssueType.id": (v67/*: any*/),
        "node.prevIssueType.name": (v68/*: any*/),
        "node.previousStatus": (v68/*: any*/),
        "node.previousTitle": (v68/*: any*/),
        "node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.project.id": (v67/*: any*/),
        "node.project.title": (v68/*: any*/),
        "node.project.url": (v70/*: any*/),
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
        "node.reactionGroups.reactors.nodes.__isNode": (v68/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v68/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v67/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v68/*: any*/),
        "node.reactionGroups.reactors.totalCount": (v76/*: any*/),
        "node.reactionGroups.viewerHasReacted": (v71/*: any*/),
        "node.referencedAt": (v72/*: any*/),
        "node.repository": (v77/*: any*/),
        "node.repository.databaseId": (v83/*: any*/),
        "node.repository.id": (v67/*: any*/),
        "node.repository.isPrivate": (v71/*: any*/),
        "node.repository.name": (v68/*: any*/),
        "node.repository.nameWithOwner": (v68/*: any*/),
        "node.repository.owner": (v78/*: any*/),
        "node.repository.owner.__typename": (v68/*: any*/),
        "node.repository.owner.id": (v67/*: any*/),
        "node.repository.owner.login": (v68/*: any*/),
        "node.repository.owner.url": (v70/*: any*/),
        "node.repository.slashCommandsEnabled": (v71/*: any*/),
        "node.showSpammyBadge": (v71/*: any*/),
        "node.source": (v84/*: any*/),
        "node.source.__isNode": (v68/*: any*/),
        "node.source.__typename": (v68/*: any*/),
        "node.source.id": (v67/*: any*/),
        "node.stateReason": (v80/*: any*/),
        "node.status": (v68/*: any*/),
        "node.subIssue": (v88/*: any*/),
        "node.subIssue.__isReferencedSubject": (v68/*: any*/),
        "node.subIssue.__typename": (v68/*: any*/),
        "node.subIssue.databaseId": (v83/*: any*/),
        "node.subIssue.id": (v67/*: any*/),
        "node.subIssue.isDraft": (v71/*: any*/),
        "node.subIssue.isInMergeQueue": (v71/*: any*/),
        "node.subIssue.issueTitleHTML": (v68/*: any*/),
        "node.subIssue.number": (v76/*: any*/),
        "node.subIssue.pullTitleHTML": (v74/*: any*/),
        "node.subIssue.repository": (v77/*: any*/),
        "node.subIssue.repository.id": (v67/*: any*/),
        "node.subIssue.repository.isPrivate": (v71/*: any*/),
        "node.subIssue.repository.name": (v68/*: any*/),
        "node.subIssue.repository.owner": (v78/*: any*/),
        "node.subIssue.repository.owner.__typename": (v68/*: any*/),
        "node.subIssue.repository.owner.id": (v67/*: any*/),
        "node.subIssue.repository.owner.login": (v68/*: any*/),
        "node.subIssue.state": (v79/*: any*/),
        "node.subIssue.stateReason": (v80/*: any*/),
        "node.subIssue.url": (v70/*: any*/),
        "node.subject": (v84/*: any*/),
        "node.subject.__isNode": (v68/*: any*/),
        "node.subject.__typename": (v68/*: any*/),
        "node.subject.id": (v67/*: any*/),
        "node.subject.isDraft": (v71/*: any*/),
        "node.subject.isInMergeQueue": (v71/*: any*/),
        "node.subject.number": (v76/*: any*/),
        "node.subject.repository": (v77/*: any*/),
        "node.subject.repository.id": (v67/*: any*/),
        "node.subject.repository.name": (v68/*: any*/),
        "node.subject.repository.owner": (v78/*: any*/),
        "node.subject.repository.owner.__typename": (v68/*: any*/),
        "node.subject.repository.owner.id": (v67/*: any*/),
        "node.subject.repository.owner.login": (v68/*: any*/),
        "node.subject.state": (v79/*: any*/),
        "node.subject.title": (v68/*: any*/),
        "node.subject.url": (v70/*: any*/),
        "node.target": (v84/*: any*/),
        "node.target.__isNode": (v68/*: any*/),
        "node.target.__typename": (v68/*: any*/),
        "node.target.id": (v67/*: any*/),
        "node.target.repository": (v77/*: any*/),
        "node.target.repository.id": (v67/*: any*/),
        "node.url": (v70/*: any*/),
        "node.viewerCanBlockFromOrg": (v71/*: any*/),
        "node.viewerCanDelete": (v71/*: any*/),
        "node.viewerCanMinimize": (v71/*: any*/),
        "node.viewerCanReadUserContentEdits": (v71/*: any*/),
        "node.viewerCanReport": (v71/*: any*/),
        "node.viewerCanReportToMaintainer": (v71/*: any*/),
        "node.viewerCanUnblockFromOrg": (v71/*: any*/),
        "node.viewerCanUndo": (v71/*: any*/),
        "node.viewerCanUpdate": (v71/*: any*/),
        "node.viewerDidAuthor": (v71/*: any*/),
        "node.willCloseSubject": (v71/*: any*/),
        "node.willCloseTarget": (v71/*: any*/)
      }
    },
    "name": "IssueTimelineItemTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e0e5fd72003e6203539be74783916977";

export default node;
