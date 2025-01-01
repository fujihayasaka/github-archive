/**
 * @generated SignedSource<<964e8161feb811c4ca6946b06a04e9bc>>
 * @relayHash aa75a87e6bfdded1dac8af60a2fb264c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID aa75a87e6bfdded1dac8af60a2fb264c

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type NewIssueTimelineItemTestQuery$variables = {
  id: string;
};
export type NewIssueTimelineItemTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"NewIssueTimelineItem">;
  } | null | undefined;
};
export type NewIssueTimelineItemTestQuery = {
  response: NewIssueTimelineItemTestQuery$data;
  variables: NewIssueTimelineItemTestQuery$variables;
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
  "name": "willCloseTarget",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v10 = [
  (v9/*: any*/)
],
v11 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": (v10/*: any*/),
    "storageKey": null
  }
],
v12 = {
  "kind": "InlineFragment",
  "selections": (v10/*: any*/),
  "type": "User",
  "abstractKey": null
},
v13 = {
  "kind": "InlineFragment",
  "selections": (v10/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v14 = {
  "kind": "InlineFragment",
  "selections": (v10/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v15 = {
  "kind": "InlineFragment",
  "selections": (v10/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v16 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": (v10/*: any*/),
    "storageKey": null
  }
],
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
v18 = [
  (v2/*: any*/),
  (v5/*: any*/),
  (v9/*: any*/)
],
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
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
  "selections": (v10/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v26 = [
  (v2/*: any*/),
  (v25/*: any*/)
],
v27 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
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
v29 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v18/*: any*/),
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v9/*: any*/),
    (v22/*: any*/),
    (v23/*: any*/),
    (v29/*: any*/)
  ],
  "storageKey": null
},
v31 = {
  "kind": "InlineFragment",
  "selections": [
    (v9/*: any*/),
    (v27/*: any*/),
    (v20/*: any*/),
    (v19/*: any*/),
    (v28/*: any*/),
    (v30/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v32 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v36 = {
  "kind": "InlineFragment",
  "selections": [
    (v9/*: any*/),
    (v32/*: any*/),
    (v20/*: any*/),
    (v19/*: any*/),
    (v33/*: any*/),
    (v34/*: any*/),
    (v35/*: any*/),
    (v30/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v37 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v38 = {
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
v39 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v37/*: any*/),
    (v38/*: any*/),
    (v5/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v40 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v9/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v22/*: any*/),
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
  (v3/*: any*/),
  (v4/*: any*/),
  (v39/*: any*/)
],
v41 = [
  (v9/*: any*/),
  (v5/*: any*/)
],
v42 = {
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
      "selections": (v41/*: any*/),
      "type": "User",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v41/*: any*/),
      "type": "Bot",
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
    (v25/*: any*/)
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
      (v9/*: any*/),
      (v20/*: any*/)
    ],
    "storageKey": null
  },
  (v3/*: any*/),
  (v4/*: any*/),
  (v39/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "milestoneTitle",
    "storageKey": null
  }
],
v44 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v22/*: any*/),
    (v20/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v46 = [
  (v4/*: any*/),
  (v3/*: any*/),
  (v39/*: any*/)
],
v47 = {
  "kind": "InlineFragment",
  "selections": [
    (v31/*: any*/),
    (v36/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v22/*: any*/),
    (v29/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v51 = [
  (v3/*: any*/),
  (v4/*: any*/),
  (v39/*: any*/)
],
v52 = [
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
v53 = [
  (v3/*: any*/),
  (v39/*: any*/),
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
          (v48/*: any*/),
          (v20/*: any*/),
          (v19/*: any*/),
          (v33/*: any*/),
          (v34/*: any*/),
          (v35/*: any*/),
          (v49/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v25/*: any*/)
    ],
    "storageKey": null
  }
],
v54 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v27/*: any*/),
        (v20/*: any*/),
        (v28/*: any*/),
        (v30/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v32/*: any*/),
        (v20/*: any*/),
        (v33/*: any*/),
        (v34/*: any*/),
        (v35/*: any*/),
        (v30/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v55 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v56 = [
  (v47/*: any*/)
],
v57 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v48/*: any*/),
    (v20/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v59 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v60 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v61 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v62 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v63 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v64 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v65 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v66 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v67 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v68 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v69 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v70 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v71 = {
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
v72 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v73 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v74 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v75 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v76 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "NewIssueTimelineItemTestQuery",
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
            "name": "NewIssueTimelineItem",
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
                      (v8/*: any*/)
                    ],
                    "type": "CrossReferencedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v11/*: any*/),
                    "type": "LabeledEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v11/*: any*/),
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
                          (v12/*: any*/),
                          (v13/*: any*/),
                          (v14/*: any*/),
                          (v15/*: any*/)
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
                          (v12/*: any*/),
                          (v13/*: any*/),
                          (v14/*: any*/),
                          (v15/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "type": "UnassignedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v16/*: any*/),
                    "type": "MilestonedEvent",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v16/*: any*/),
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
                    "name": "AddedToProjectEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "MovedColumnsInProjectEvent"
                  },
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "RemovedFromProjectEvent"
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
                    "name": "ConvertedNoteToIssueEvent"
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
                  (v17/*: any*/)
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
    "name": "NewIssueTimelineItemTestQuery",
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
          (v9/*: any*/),
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
                    "selections": (v18/*: any*/),
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
                        "selections": (v18/*: any*/),
                        "storageKey": null
                      },
                      (v9/*: any*/),
                      (v19/*: any*/),
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
                  (v20/*: any*/),
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
                      (v2/*: any*/),
                      (v9/*: any*/),
                      (v5/*: any*/),
                      (v21/*: any*/)
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
                          (v9/*: any*/),
                          (v5/*: any*/),
                          (v20/*: any*/)
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
                              (v20/*: any*/),
                              (v5/*: any*/),
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
                  (v8/*: any*/),
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
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": (v10/*: any*/),
                            "storageKey": null
                          }
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
                      (v31/*: any*/),
                      (v36/*: any*/),
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v39/*: any*/)
                ],
                "type": "CrossReferencedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v40/*: any*/),
                "type": "LabeledEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v40/*: any*/),
                "type": "UnlabeledEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v42/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v39/*: any*/)
                ],
                "type": "AssignedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v42/*: any*/),
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
                      (v37/*: any*/),
                      (v38/*: any*/),
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
                "selections": [
                  (v4/*: any*/),
                  (v39/*: any*/),
                  (v44/*: any*/),
                  (v45/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "AddedToProjectEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v3/*: any*/),
                  (v39/*: any*/),
                  (v44/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "previousProjectColumnName",
                    "storageKey": null
                  },
                  (v45/*: any*/)
                ],
                "type": "MovedColumnsInProjectEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v3/*: any*/),
                  (v39/*: any*/),
                  (v44/*: any*/),
                  (v45/*: any*/)
                ],
                "type": "RemovedFromProjectEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v46/*: any*/),
                "type": "SubscribedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v46/*: any*/),
                "type": "UnsubscribedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v46/*: any*/),
                "type": "MentionedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v28/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "duplicateOf",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v47/*: any*/),
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
                          (v20/*: any*/),
                          (v48/*: any*/)
                        ],
                        "type": "ProjectV2",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v20/*: any*/),
                          (v19/*: any*/),
                          (v49/*: any*/)
                        ],
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v20/*: any*/),
                          (v50/*: any*/),
                          (v49/*: any*/)
                        ],
                        "type": "Commit",
                        "abstractKey": null
                      },
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v39/*: any*/)
                ],
                "type": "ClosedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
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
                  (v39/*: any*/)
                ],
                "type": "LockedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
                "type": "UnlockedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
                "type": "PinnedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v51/*: any*/),
                "type": "UnpinnedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v39/*: any*/),
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
                  (v39/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "deletedCommentAuthor",
                    "plural": false,
                    "selections": (v18/*: any*/),
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
                  (v39/*: any*/),
                  {
                    "alias": "blockedUser",
                    "args": null,
                    "concreteType": "User",
                    "kind": "LinkedField",
                    "name": "subject",
                    "plural": false,
                    "selections": [
                      (v5/*: any*/),
                      (v9/*: any*/)
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
                  (v39/*: any*/),
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
                      (v20/*: any*/),
                      (v50/*: any*/),
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
                              (v21/*: any*/),
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v33/*: any*/),
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
                                "selections": (v52/*: any*/),
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "CertificateAttributes",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": (v52/*: any*/),
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
                          (v29/*: any*/),
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
                  (v4/*: any*/)
                ],
                "type": "ReferencedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v53/*: any*/),
                "type": "ConnectedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v39/*: any*/),
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
                      (v20/*: any*/),
                      (v9/*: any*/)
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
                  (v3/*: any*/),
                  (v39/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Project",
                    "kind": "LinkedField",
                    "name": "project",
                    "plural": false,
                    "selections": [
                      (v20/*: any*/),
                      (v22/*: any*/),
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "type": "ConvertedNoteToIssueEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v53/*: any*/),
                "type": "DisconnectedEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v39/*: any*/),
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
                          (v9/*: any*/),
                          (v19/*: any*/),
                          (v54/*: any*/)
                        ],
                        "type": "Issue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v19/*: any*/),
                          (v9/*: any*/),
                          (v54/*: any*/)
                        ],
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v55/*: any*/),
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
                  (v39/*: any*/),
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
                        "selections": (v56/*: any*/),
                        "type": "Issue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": (v56/*: any*/),
                        "type": "PullRequest",
                        "abstractKey": null
                      },
                      (v25/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v55/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "UnmarkedAsDuplicateEvent",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v3/*: any*/),
                  (v39/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Discussion",
                    "kind": "LinkedField",
                    "name": "discussion",
                    "plural": false,
                    "selections": [
                      (v20/*: any*/),
                      (v19/*: any*/),
                      (v9/*: any*/)
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
                  (v39/*: any*/),
                  (v57/*: any*/)
                ],
                "type": "AddedToProjectV2Event",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v39/*: any*/),
                  (v57/*: any*/)
                ],
                "type": "RemovedFromProjectV2Event",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
                  (v39/*: any*/),
                  (v57/*: any*/),
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
                  (v39/*: any*/),
                  (v3/*: any*/)
                ],
                "type": "ConvertedFromDraftEvent",
                "abstractKey": null
              },
              (v17/*: any*/)
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
    "id": "aa75a87e6bfdded1dac8af60a2fb264c",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__id": (v58/*: any*/),
        "node.__isComment": (v59/*: any*/),
        "node.__isIssueTimelineItems": (v59/*: any*/),
        "node.__isReactable": (v59/*: any*/),
        "node.__isTimelineEvent": (v59/*: any*/),
        "node.__typename": (v59/*: any*/),
        "node.actor": (v60/*: any*/),
        "node.actor.__isActor": (v59/*: any*/),
        "node.actor.__typename": (v59/*: any*/),
        "node.actor.avatarUrl": (v61/*: any*/),
        "node.actor.id": (v58/*: any*/),
        "node.actor.login": (v59/*: any*/),
        "node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "node.assignee.__isNode": (v59/*: any*/),
        "node.assignee.__typename": (v59/*: any*/),
        "node.assignee.id": (v58/*: any*/),
        "node.assignee.login": (v59/*: any*/),
        "node.author": (v60/*: any*/),
        "node.author.__typename": (v59/*: any*/),
        "node.author.avatarUrl": (v61/*: any*/),
        "node.author.id": (v58/*: any*/),
        "node.author.login": (v59/*: any*/),
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
        "node.authorToRepoOwnerSponsorship.createdAt": (v62/*: any*/),
        "node.authorToRepoOwnerSponsorship.id": (v58/*: any*/),
        "node.authorToRepoOwnerSponsorship.isActive": (v63/*: any*/),
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
        "node.blockedUser": (v64/*: any*/),
        "node.blockedUser.id": (v58/*: any*/),
        "node.blockedUser.login": (v59/*: any*/),
        "node.body": (v59/*: any*/),
        "node.bodyHTML": (v65/*: any*/),
        "node.bodyVersion": (v59/*: any*/),
        "node.canonical": (v66/*: any*/),
        "node.canonical.__isNode": (v59/*: any*/),
        "node.canonical.__isReferencedSubject": (v59/*: any*/),
        "node.canonical.__typename": (v59/*: any*/),
        "node.canonical.id": (v58/*: any*/),
        "node.canonical.isDraft": (v63/*: any*/),
        "node.canonical.isInMergeQueue": (v63/*: any*/),
        "node.canonical.issueTitleHTML": (v59/*: any*/),
        "node.canonical.number": (v67/*: any*/),
        "node.canonical.pullTitleHTML": (v65/*: any*/),
        "node.canonical.repository": (v68/*: any*/),
        "node.canonical.repository.id": (v58/*: any*/),
        "node.canonical.repository.isPrivate": (v63/*: any*/),
        "node.canonical.repository.name": (v59/*: any*/),
        "node.canonical.repository.owner": (v69/*: any*/),
        "node.canonical.repository.owner.__typename": (v59/*: any*/),
        "node.canonical.repository.owner.id": (v58/*: any*/),
        "node.canonical.repository.owner.login": (v59/*: any*/),
        "node.canonical.state": (v70/*: any*/),
        "node.canonical.stateReason": (v71/*: any*/),
        "node.canonical.url": (v61/*: any*/),
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v59/*: any*/),
        "node.closer.__typename": (v59/*: any*/),
        "node.closer.abbreviatedOid": (v59/*: any*/),
        "node.closer.id": (v58/*: any*/),
        "node.closer.number": (v67/*: any*/),
        "node.closer.repository": (v68/*: any*/),
        "node.closer.repository.id": (v58/*: any*/),
        "node.closer.repository.name": (v59/*: any*/),
        "node.closer.repository.owner": (v69/*: any*/),
        "node.closer.repository.owner.__typename": (v59/*: any*/),
        "node.closer.repository.owner.id": (v58/*: any*/),
        "node.closer.repository.owner.login": (v59/*: any*/),
        "node.closer.title": (v59/*: any*/),
        "node.closer.url": (v61/*: any*/),
        "node.closingProjectItemStatus": (v72/*: any*/),
        "node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "node.commit.abbreviatedOid": (v59/*: any*/),
        "node.commit.hasSignature": (v63/*: any*/),
        "node.commit.id": (v58/*: any*/),
        "node.commit.message": (v59/*: any*/),
        "node.commit.messageBodyHTML": (v65/*: any*/),
        "node.commit.messageHeadlineHTML": (v65/*: any*/),
        "node.commit.repository": (v68/*: any*/),
        "node.commit.repository.defaultBranch": (v59/*: any*/),
        "node.commit.repository.id": (v58/*: any*/),
        "node.commit.repository.name": (v59/*: any*/),
        "node.commit.repository.owner": (v69/*: any*/),
        "node.commit.repository.owner.__typename": (v59/*: any*/),
        "node.commit.repository.owner.id": (v58/*: any*/),
        "node.commit.repository.owner.login": (v59/*: any*/),
        "node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "node.commit.signature.__typename": (v59/*: any*/),
        "node.commit.signature.issuer": (v73/*: any*/),
        "node.commit.signature.issuer.commonName": (v72/*: any*/),
        "node.commit.signature.issuer.emailAddress": (v72/*: any*/),
        "node.commit.signature.issuer.organization": (v72/*: any*/),
        "node.commit.signature.issuer.organizationUnit": (v72/*: any*/),
        "node.commit.signature.keyFingerprint": (v72/*: any*/),
        "node.commit.signature.keyId": (v72/*: any*/),
        "node.commit.signature.signer": (v64/*: any*/),
        "node.commit.signature.signer.avatarUrl": (v61/*: any*/),
        "node.commit.signature.signer.id": (v58/*: any*/),
        "node.commit.signature.signer.login": (v59/*: any*/),
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
        "node.commit.signature.subject": (v73/*: any*/),
        "node.commit.signature.subject.commonName": (v72/*: any*/),
        "node.commit.signature.subject.emailAddress": (v72/*: any*/),
        "node.commit.signature.subject.organization": (v72/*: any*/),
        "node.commit.signature.subject.organizationUnit": (v72/*: any*/),
        "node.commit.signature.wasSignedByGitHub": (v63/*: any*/),
        "node.commit.url": (v61/*: any*/),
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
        "node.createdAt": (v62/*: any*/),
        "node.createdViaEmail": (v63/*: any*/),
        "node.currentTitle": (v59/*: any*/),
        "node.databaseId": (v74/*: any*/),
        "node.deletedCommentAuthor": (v60/*: any*/),
        "node.deletedCommentAuthor.__typename": (v59/*: any*/),
        "node.deletedCommentAuthor.id": (v58/*: any*/),
        "node.deletedCommentAuthor.login": (v59/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v58/*: any*/),
        "node.discussion.number": (v67/*: any*/),
        "node.discussion.url": (v61/*: any*/),
        "node.duplicateOf": (v66/*: any*/),
        "node.duplicateOf.__isNode": (v59/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v59/*: any*/),
        "node.duplicateOf.__typename": (v59/*: any*/),
        "node.duplicateOf.id": (v58/*: any*/),
        "node.duplicateOf.isDraft": (v63/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v63/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v59/*: any*/),
        "node.duplicateOf.number": (v67/*: any*/),
        "node.duplicateOf.pullTitleHTML": (v65/*: any*/),
        "node.duplicateOf.repository": (v68/*: any*/),
        "node.duplicateOf.repository.id": (v58/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v63/*: any*/),
        "node.duplicateOf.repository.name": (v59/*: any*/),
        "node.duplicateOf.repository.owner": (v69/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v59/*: any*/),
        "node.duplicateOf.repository.owner.id": (v58/*: any*/),
        "node.duplicateOf.repository.owner.login": (v59/*: any*/),
        "node.duplicateOf.state": (v70/*: any*/),
        "node.duplicateOf.stateReason": (v71/*: any*/),
        "node.duplicateOf.url": (v61/*: any*/),
        "node.fromRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.fromRepository.id": (v58/*: any*/),
        "node.fromRepository.nameWithOwner": (v59/*: any*/),
        "node.fromRepository.url": (v61/*: any*/),
        "node.id": (v58/*: any*/),
        "node.innerSource": (v75/*: any*/),
        "node.innerSource.__isNode": (v59/*: any*/),
        "node.innerSource.__isReferencedSubject": (v59/*: any*/),
        "node.innerSource.__typename": (v59/*: any*/),
        "node.innerSource.id": (v58/*: any*/),
        "node.innerSource.isDraft": (v63/*: any*/),
        "node.innerSource.isInMergeQueue": (v63/*: any*/),
        "node.innerSource.issueTitleHTML": (v59/*: any*/),
        "node.innerSource.number": (v67/*: any*/),
        "node.innerSource.pullTitleHTML": (v65/*: any*/),
        "node.innerSource.repository": (v68/*: any*/),
        "node.innerSource.repository.id": (v58/*: any*/),
        "node.innerSource.repository.isPrivate": (v63/*: any*/),
        "node.innerSource.repository.name": (v59/*: any*/),
        "node.innerSource.repository.owner": (v69/*: any*/),
        "node.innerSource.repository.owner.__typename": (v59/*: any*/),
        "node.innerSource.repository.owner.id": (v58/*: any*/),
        "node.innerSource.repository.owner.login": (v59/*: any*/),
        "node.innerSource.state": (v70/*: any*/),
        "node.innerSource.stateReason": (v71/*: any*/),
        "node.innerSource.url": (v61/*: any*/),
        "node.isCanonicalOfClosedDuplicate": (v76/*: any*/),
        "node.isHidden": (v63/*: any*/),
        "node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "node.issue.author": (v60/*: any*/),
        "node.issue.author.__typename": (v59/*: any*/),
        "node.issue.author.id": (v58/*: any*/),
        "node.issue.author.login": (v59/*: any*/),
        "node.issue.databaseId": (v74/*: any*/),
        "node.issue.id": (v58/*: any*/),
        "node.issue.locked": (v63/*: any*/),
        "node.issue.number": (v67/*: any*/),
        "node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "node.label.color": (v59/*: any*/),
        "node.label.description": (v72/*: any*/),
        "node.label.id": (v58/*: any*/),
        "node.label.name": (v59/*: any*/),
        "node.label.nameHTML": (v59/*: any*/),
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
        "node.lastUserContentEdit.editor": (v60/*: any*/),
        "node.lastUserContentEdit.editor.__typename": (v59/*: any*/),
        "node.lastUserContentEdit.editor.id": (v58/*: any*/),
        "node.lastUserContentEdit.editor.login": (v59/*: any*/),
        "node.lastUserContentEdit.editor.url": (v61/*: any*/),
        "node.lastUserContentEdit.id": (v58/*: any*/),
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
        "node.milestone.id": (v58/*: any*/),
        "node.milestone.url": (v61/*: any*/),
        "node.milestoneTitle": (v59/*: any*/),
        "node.minimizedReason": (v72/*: any*/),
        "node.pendingBlock": (v76/*: any*/),
        "node.pendingMinimizeReason": (v72/*: any*/),
        "node.pendingUnblock": (v76/*: any*/),
        "node.pendingUndo": (v76/*: any*/),
        "node.previousProjectColumnName": (v59/*: any*/),
        "node.previousStatus": (v59/*: any*/),
        "node.previousTitle": (v59/*: any*/),
        "node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Project"
        },
        "node.project.id": (v58/*: any*/),
        "node.project.name": (v59/*: any*/),
        "node.project.title": (v59/*: any*/),
        "node.project.url": (v61/*: any*/),
        "node.projectColumnName": (v59/*: any*/),
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
        "node.reactionGroups.reactors.nodes.__isNode": (v59/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v59/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v58/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v59/*: any*/),
        "node.reactionGroups.reactors.totalCount": (v67/*: any*/),
        "node.reactionGroups.viewerHasReacted": (v63/*: any*/),
        "node.referencedAt": (v62/*: any*/),
        "node.repository": (v68/*: any*/),
        "node.repository.databaseId": (v74/*: any*/),
        "node.repository.id": (v58/*: any*/),
        "node.repository.isPrivate": (v63/*: any*/),
        "node.repository.name": (v59/*: any*/),
        "node.repository.nameWithOwner": (v59/*: any*/),
        "node.repository.owner": (v69/*: any*/),
        "node.repository.owner.__typename": (v59/*: any*/),
        "node.repository.owner.id": (v58/*: any*/),
        "node.repository.owner.login": (v59/*: any*/),
        "node.repository.owner.url": (v61/*: any*/),
        "node.repository.slashCommandsEnabled": (v63/*: any*/),
        "node.showSpammyBadge": (v63/*: any*/),
        "node.source": (v75/*: any*/),
        "node.source.__isNode": (v59/*: any*/),
        "node.source.__typename": (v59/*: any*/),
        "node.source.id": (v58/*: any*/),
        "node.stateReason": (v71/*: any*/),
        "node.status": (v59/*: any*/),
        "node.subject": (v75/*: any*/),
        "node.subject.__isNode": (v59/*: any*/),
        "node.subject.__typename": (v59/*: any*/),
        "node.subject.id": (v58/*: any*/),
        "node.subject.isDraft": (v63/*: any*/),
        "node.subject.isInMergeQueue": (v63/*: any*/),
        "node.subject.number": (v67/*: any*/),
        "node.subject.repository": (v68/*: any*/),
        "node.subject.repository.id": (v58/*: any*/),
        "node.subject.repository.name": (v59/*: any*/),
        "node.subject.repository.owner": (v69/*: any*/),
        "node.subject.repository.owner.__typename": (v59/*: any*/),
        "node.subject.repository.owner.id": (v58/*: any*/),
        "node.subject.repository.owner.login": (v59/*: any*/),
        "node.subject.state": (v70/*: any*/),
        "node.subject.title": (v59/*: any*/),
        "node.subject.url": (v61/*: any*/),
        "node.target": (v75/*: any*/),
        "node.target.__isNode": (v59/*: any*/),
        "node.target.__typename": (v59/*: any*/),
        "node.target.id": (v58/*: any*/),
        "node.target.repository": (v68/*: any*/),
        "node.target.repository.id": (v58/*: any*/),
        "node.url": (v61/*: any*/),
        "node.viewerCanBlockFromOrg": (v63/*: any*/),
        "node.viewerCanDelete": (v63/*: any*/),
        "node.viewerCanMinimize": (v63/*: any*/),
        "node.viewerCanReadUserContentEdits": (v63/*: any*/),
        "node.viewerCanReport": (v63/*: any*/),
        "node.viewerCanReportToMaintainer": (v63/*: any*/),
        "node.viewerCanUnblockFromOrg": (v63/*: any*/),
        "node.viewerCanUndo": (v63/*: any*/),
        "node.viewerCanUpdate": (v63/*: any*/),
        "node.viewerDidAuthor": (v63/*: any*/),
        "node.willCloseSubject": (v63/*: any*/),
        "node.willCloseTarget": (v63/*: any*/)
      }
    },
    "name": "NewIssueTimelineItemTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "6bc14818992f2eed7fcd77c89071fef5";

export default node;
