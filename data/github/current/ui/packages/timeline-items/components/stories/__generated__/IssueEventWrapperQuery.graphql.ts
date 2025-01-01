/**
 * @generated SignedSource<<7cacd7538af9ad8a5f89a6adc8f4d339>>
 * @relayHash 65e72c04c690c7341533b1164118333f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 65e72c04c690c7341533b1164118333f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueEventWrapperQuery$variables = Record<PropertyKey, never>;
export type IssueEventWrapperQuery$data = {
  readonly node: {
    readonly __typename: string;
    readonly " $fragmentSpreads": FragmentRefs<"AddedToProjectV2Event" | "AssignedEvent" | "ClosedEvent" | "CommentDeletedEvent" | "ConnectedEvent" | "ConvertedFromDraftEvent" | "ConvertedToDiscussionEvent" | "CrossReferencedEvent" | "DemilestonedEvent" | "DisconnectedEvent" | "IssueComment_issueComment" | "IssueTypeAddedEvent" | "IssueTypeChangedEvent" | "IssueTypeRemovedEvent" | "LabeledEvent" | "LockedEvent" | "MarkedAsDuplicateEvent" | "MentionedEvent" | "MilestonedEvent" | "ParentIssueAddedEvent" | "ParentIssueRemovedEvent" | "PinnedEvent" | "ProjectV2ItemStatusChangedEvent" | "ReactionViewerRelayGroups" | "ReferencedEvent" | "RemovedFromProjectV2Event" | "RenamedTitleEvent" | "ReopenedEvent" | "SubIssueAddedEvent" | "SubIssueRemovedEvent" | "SubscribedEvent" | "TransferredEvent" | "UnassignedEvent" | "UnlabeledEvent" | "UnlockedEvent" | "UnmarkedAsDuplicateEvent" | "UnpinnedEvent" | "UnsubscribedEvent" | "UserBlockedEvent">;
  } | null | undefined;
};
export type IssueEventWrapperQuery = {
  response: IssueEventWrapperQuery$data;
  variables: IssueEventWrapperQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "SSC_asdkasd"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
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
  "name": "databaseId",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
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
  "name": "avatarUrl",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v12 = [
  (v1/*: any*/),
  (v6/*: any*/),
  (v2/*: any*/)
],
v13 = [
  (v6/*: any*/)
],
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCopilot",
  "storageKey": null
},
v15 = [
  (v2/*: any*/)
],
v16 = {
  "kind": "InlineFragment",
  "selections": (v15/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v17 = {
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
                (v1/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": (v13/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v6/*: any*/),
                    (v14/*: any*/)
                  ],
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v13/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v13/*: any*/),
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
},
v18 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v19 = {
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
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v21 = {
  "kind": "InlineFragment",
  "selections": [
    (v14/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v1/*: any*/),
    (v18/*: any*/),
    (v19/*: any*/),
    (v6/*: any*/),
    (v20/*: any*/),
    (v21/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v23 = [
  (v5/*: any*/),
  (v3/*: any*/),
  (v22/*: any*/)
],
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
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v12/*: any*/),
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v8/*: any*/),
    (v9/*: any*/),
    (v26/*: any*/)
  ],
  "storageKey": null
},
v28 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v25/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v24/*: any*/),
    (v27/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v29 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v33 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v29/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v30/*: any*/),
    (v31/*: any*/),
    (v32/*: any*/),
    (v27/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v28/*: any*/),
    (v33/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v36 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v26/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v38 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v22/*: any*/)
],
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v40 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v22/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v8/*: any*/),
      (v39/*: any*/),
      (v2/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "description",
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v42 = [
  (v41/*: any*/)
],
v43 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "assignee",
  "plural": false,
  "selections": [
    (v1/*: any*/),
    {
      "kind": "InlineFragment",
      "selections": [
        (v6/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v42/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v42/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v42/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v41/*: any*/),
            (v14/*: any*/)
          ],
          "type": "Bot",
          "abstractKey": null
        }
      ],
      "type": "Actor",
      "abstractKey": "__isActor"
    },
    (v16/*: any*/)
  ],
  "storageKey": null
},
v44 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v22/*: any*/),
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
      (v4/*: any*/),
      (v2/*: any*/)
    ],
    "storageKey": null
  }
],
v45 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v15/*: any*/),
  "storageKey": null
},
v46 = [
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
v47 = [
  (v3/*: any*/),
  (v22/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": null,
    "kind": "LinkedField",
    "name": "subject",
    "plural": false,
    "selections": [
      (v1/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v35/*: any*/),
          (v4/*: any*/),
          (v11/*: any*/),
          (v30/*: any*/),
          (v31/*: any*/),
          (v32/*: any*/),
          (v36/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v16/*: any*/)
    ],
    "storageKey": null
  }
],
v48 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v25/*: any*/),
        (v4/*: any*/),
        (v24/*: any*/),
        (v27/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v29/*: any*/),
        (v4/*: any*/),
        (v30/*: any*/),
        (v31/*: any*/),
        (v32/*: any*/),
        (v27/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v50 = [
  (v34/*: any*/)
],
v51 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v35/*: any*/),
    (v4/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v52 = [
  (v3/*: any*/),
  (v22/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v3/*: any*/),
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v1/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v25/*: any*/),
              (v4/*: any*/),
              (v11/*: any*/),
              (v24/*: any*/),
              (v27/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v29/*: any*/),
              (v4/*: any*/),
              (v11/*: any*/),
              (v30/*: any*/),
              (v31/*: any*/),
              (v32/*: any*/),
              (v27/*: any*/)
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
v53 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v9/*: any*/),
    (v26/*: any*/)
  ],
  "storageKey": null
},
v54 = [
  (v3/*: any*/),
  (v22/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v45/*: any*/),
      (v3/*: any*/),
      (v2/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v1/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v25/*: any*/),
              (v4/*: any*/),
              (v11/*: any*/),
              (v24/*: any*/),
              (v53/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v29/*: any*/),
              (v4/*: any*/),
              (v11/*: any*/),
              (v30/*: any*/),
              (v31/*: any*/),
              (v32/*: any*/),
              (v53/*: any*/)
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
v55 = [
  (v8/*: any*/),
  (v39/*: any*/),
  (v2/*: any*/)
],
v56 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v55/*: any*/),
  "storageKey": null
},
v57 = [
  (v3/*: any*/),
  (v22/*: any*/),
  (v5/*: any*/),
  (v56/*: any*/)
],
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v61 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v62 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v63 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
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
},
v77 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v78 = {
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
v79 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueEventWrapperQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "IssueComment_issueComment"
          },
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "ReactionViewerRelayGroups"
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
          }
        ],
        "storageKey": "node(id:\"SSC_asdkasd\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueEventWrapperQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
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
              (v4/*: any*/),
              (v5/*: any*/),
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
                "kind": "ScalarField",
                "name": "viewerDidAuthor",
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
                  (v5/*: any*/),
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
                  (v1/*: any*/),
                  (v2/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/)
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
                  (v8/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v1/*: any*/),
                      (v2/*: any*/),
                      (v6/*: any*/),
                      (v4/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "slashCommandsEnabled",
                    "storageKey": null
                  },
                  (v10/*: any*/),
                  (v3/*: any*/)
                ],
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
                  (v11/*: any*/),
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "locked",
                    "storageKey": null
                  },
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "author",
                    "plural": false,
                    "selections": (v12/*: any*/),
                    "storageKey": null
                  }
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
                          (v1/*: any*/),
                          (v4/*: any*/),
                          (v6/*: any*/),
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
              (v17/*: any*/)
            ],
            "type": "IssueComment",
            "abstractKey": null
          },
          (v17/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": (v23/*: any*/),
            "type": "SubscribedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v23/*: any*/),
            "type": "UnsubscribedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v23/*: any*/),
            "type": "MentionedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v24/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  (v34/*: any*/),
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
                  (v1/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v35/*: any*/)
                    ],
                    "type": "ProjectV2",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v11/*: any*/),
                      (v36/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v37/*: any*/),
                      (v36/*: any*/)
                    ],
                    "type": "Commit",
                    "abstractKey": null
                  },
                  (v16/*: any*/)
                ],
                "storageKey": null
              },
              (v22/*: any*/)
            ],
            "type": "ClosedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v38/*: any*/),
            "type": "ReopenedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "lockReason",
                "storageKey": null
              },
              (v22/*: any*/)
            ],
            "type": "LockedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v38/*: any*/),
            "type": "UnlockedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v38/*: any*/),
            "type": "PinnedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v38/*: any*/),
            "type": "UnpinnedEvent",
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
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v22/*: any*/),
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
            "selections": (v40/*: any*/),
            "type": "UnlabeledEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "actor",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  (v6/*: any*/),
                  (v18/*: any*/),
                  (v19/*: any*/),
                  (v20/*: any*/),
                  (v21/*: any*/),
                  (v2/*: any*/)
                ],
                "storageKey": null
              },
              (v43/*: any*/)
            ],
            "type": "UnassignedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v22/*: any*/),
              (v43/*: any*/)
            ],
            "type": "AssignedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v22/*: any*/),
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
              (v3/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "blockDuration",
                "storageKey": null
              },
              (v22/*: any*/),
              {
                "alias": "blockedUser",
                "args": null,
                "concreteType": "User",
                "kind": "LinkedField",
                "name": "subject",
                "plural": false,
                "selections": [
                  (v6/*: any*/),
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
            "selections": (v44/*: any*/),
            "type": "MilestonedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v44/*: any*/),
            "type": "DemilestonedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "referencedAt",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "willCloseTarget",
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
                  (v1/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v45/*: any*/)
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
                  (v1/*: any*/),
                  {
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isReferencedSubject"
                  },
                  (v28/*: any*/),
                  (v33/*: any*/),
                  (v16/*: any*/)
                ],
                "storageKey": null
              },
              (v22/*: any*/)
            ],
            "type": "CrossReferencedEvent",
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
                "selections": [
                  (v1/*: any*/),
                  (v16/*: any*/)
                ],
                "storageKey": null
              },
              (v22/*: any*/),
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
                  (v4/*: any*/),
                  (v37/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "signature",
                    "plural": false,
                    "selections": [
                      (v1/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "User",
                        "kind": "LinkedField",
                        "name": "signer",
                        "plural": false,
                        "selections": [
                          (v6/*: any*/),
                          (v7/*: any*/),
                          (v2/*: any*/)
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
                            "selections": (v46/*: any*/),
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "CertificateAttributes",
                            "kind": "LinkedField",
                            "name": "subject",
                            "plural": false,
                            "selections": (v46/*: any*/),
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
                      (v8/*: any*/),
                      (v26/*: any*/),
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
              (v5/*: any*/)
            ],
            "type": "ReferencedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v47/*: any*/),
            "type": "ConnectedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v22/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "fromRepository",
                "plural": false,
                "selections": [
                  (v10/*: any*/),
                  (v4/*: any*/),
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
            "selections": (v47/*: any*/),
            "type": "DisconnectedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v22/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "canonical",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v2/*: any*/),
                      (v11/*: any*/),
                      (v48/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v11/*: any*/),
                      (v2/*: any*/),
                      (v48/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  (v16/*: any*/)
                ],
                "storageKey": null
              },
              (v49/*: any*/),
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
              (v22/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "canonical",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": (v50/*: any*/),
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v50/*: any*/),
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  (v16/*: any*/)
                ],
                "storageKey": null
              },
              (v49/*: any*/),
              (v3/*: any*/)
            ],
            "type": "UnmarkedAsDuplicateEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v22/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Discussion",
                "kind": "LinkedField",
                "name": "discussion",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v11/*: any*/),
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
              (v3/*: any*/),
              (v5/*: any*/),
              (v22/*: any*/),
              (v51/*: any*/)
            ],
            "type": "AddedToProjectV2Event",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v22/*: any*/),
              (v51/*: any*/)
            ],
            "type": "RemovedFromProjectV2Event",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v22/*: any*/),
              (v51/*: any*/),
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
              (v5/*: any*/),
              (v22/*: any*/),
              (v3/*: any*/)
            ],
            "type": "ConvertedFromDraftEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v52/*: any*/),
            "type": "SubIssueAddedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v52/*: any*/),
            "type": "SubIssueRemovedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v54/*: any*/),
            "type": "ParentIssueAddedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v54/*: any*/),
            "type": "ParentIssueRemovedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v57/*: any*/),
            "type": "IssueTypeAddedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v57/*: any*/),
            "type": "IssueTypeRemovedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v22/*: any*/),
              (v5/*: any*/),
              (v56/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "prevIssueType",
                "plural": false,
                "selections": (v55/*: any*/),
                "storageKey": null
              }
            ],
            "type": "IssueTypeChangedEvent",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"SSC_asdkasd\")"
      }
    ]
  },
  "params": {
    "id": "65e72c04c690c7341533b1164118333f",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isComment": (v58/*: any*/),
        "node.__isReactable": (v58/*: any*/),
        "node.__typename": (v58/*: any*/),
        "node.actor": (v59/*: any*/),
        "node.actor.__isActor": (v58/*: any*/),
        "node.actor.__typename": (v58/*: any*/),
        "node.actor.avatarUrl": (v60/*: any*/),
        "node.actor.id": (v61/*: any*/),
        "node.actor.isCopilot": (v62/*: any*/),
        "node.actor.login": (v58/*: any*/),
        "node.actor.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "node.assignee.__isActor": (v58/*: any*/),
        "node.assignee.__isNode": (v58/*: any*/),
        "node.assignee.__typename": (v58/*: any*/),
        "node.assignee.id": (v61/*: any*/),
        "node.assignee.isCopilot": (v62/*: any*/),
        "node.assignee.login": (v58/*: any*/),
        "node.assignee.resourcePath": (v60/*: any*/),
        "node.author": (v59/*: any*/),
        "node.author.__typename": (v58/*: any*/),
        "node.author.avatarUrl": (v60/*: any*/),
        "node.author.id": (v61/*: any*/),
        "node.author.login": (v58/*: any*/),
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
        "node.authorToRepoOwnerSponsorship.createdAt": (v63/*: any*/),
        "node.authorToRepoOwnerSponsorship.id": (v61/*: any*/),
        "node.authorToRepoOwnerSponsorship.isActive": (v62/*: any*/),
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
        "node.blockedUser.id": (v61/*: any*/),
        "node.blockedUser.login": (v58/*: any*/),
        "node.body": (v58/*: any*/),
        "node.bodyHTML": (v65/*: any*/),
        "node.bodyVersion": (v58/*: any*/),
        "node.canonical": (v66/*: any*/),
        "node.canonical.__isNode": (v58/*: any*/),
        "node.canonical.__isReferencedSubject": (v58/*: any*/),
        "node.canonical.__typename": (v58/*: any*/),
        "node.canonical.id": (v61/*: any*/),
        "node.canonical.isDraft": (v62/*: any*/),
        "node.canonical.isInMergeQueue": (v62/*: any*/),
        "node.canonical.issueTitleHTML": (v58/*: any*/),
        "node.canonical.number": (v67/*: any*/),
        "node.canonical.pullTitleHTML": (v65/*: any*/),
        "node.canonical.repository": (v68/*: any*/),
        "node.canonical.repository.id": (v61/*: any*/),
        "node.canonical.repository.isPrivate": (v62/*: any*/),
        "node.canonical.repository.name": (v58/*: any*/),
        "node.canonical.repository.owner": (v69/*: any*/),
        "node.canonical.repository.owner.__typename": (v58/*: any*/),
        "node.canonical.repository.owner.id": (v61/*: any*/),
        "node.canonical.repository.owner.login": (v58/*: any*/),
        "node.canonical.state": (v70/*: any*/),
        "node.canonical.stateReason": (v71/*: any*/),
        "node.canonical.url": (v60/*: any*/),
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v58/*: any*/),
        "node.closer.__typename": (v58/*: any*/),
        "node.closer.abbreviatedOid": (v58/*: any*/),
        "node.closer.id": (v61/*: any*/),
        "node.closer.number": (v67/*: any*/),
        "node.closer.repository": (v68/*: any*/),
        "node.closer.repository.id": (v61/*: any*/),
        "node.closer.repository.name": (v58/*: any*/),
        "node.closer.repository.owner": (v69/*: any*/),
        "node.closer.repository.owner.__typename": (v58/*: any*/),
        "node.closer.repository.owner.id": (v61/*: any*/),
        "node.closer.repository.owner.login": (v58/*: any*/),
        "node.closer.title": (v58/*: any*/),
        "node.closer.url": (v60/*: any*/),
        "node.closingProjectItemStatus": (v72/*: any*/),
        "node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "node.commit.abbreviatedOid": (v58/*: any*/),
        "node.commit.hasSignature": (v62/*: any*/),
        "node.commit.id": (v61/*: any*/),
        "node.commit.message": (v58/*: any*/),
        "node.commit.messageBodyHTML": (v65/*: any*/),
        "node.commit.messageHeadlineHTML": (v65/*: any*/),
        "node.commit.repository": (v68/*: any*/),
        "node.commit.repository.defaultBranch": (v58/*: any*/),
        "node.commit.repository.id": (v61/*: any*/),
        "node.commit.repository.name": (v58/*: any*/),
        "node.commit.repository.owner": (v69/*: any*/),
        "node.commit.repository.owner.__typename": (v58/*: any*/),
        "node.commit.repository.owner.id": (v61/*: any*/),
        "node.commit.repository.owner.login": (v58/*: any*/),
        "node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "node.commit.signature.__typename": (v58/*: any*/),
        "node.commit.signature.issuer": (v73/*: any*/),
        "node.commit.signature.issuer.commonName": (v72/*: any*/),
        "node.commit.signature.issuer.emailAddress": (v72/*: any*/),
        "node.commit.signature.issuer.organization": (v72/*: any*/),
        "node.commit.signature.issuer.organizationUnit": (v72/*: any*/),
        "node.commit.signature.keyFingerprint": (v72/*: any*/),
        "node.commit.signature.keyId": (v72/*: any*/),
        "node.commit.signature.signer": (v64/*: any*/),
        "node.commit.signature.signer.avatarUrl": (v60/*: any*/),
        "node.commit.signature.signer.id": (v61/*: any*/),
        "node.commit.signature.signer.login": (v58/*: any*/),
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
        "node.commit.signature.wasSignedByGitHub": (v62/*: any*/),
        "node.commit.url": (v60/*: any*/),
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
        "node.createdAt": (v63/*: any*/),
        "node.createdViaEmail": (v62/*: any*/),
        "node.currentTitle": (v58/*: any*/),
        "node.databaseId": (v74/*: any*/),
        "node.deletedCommentAuthor": (v59/*: any*/),
        "node.deletedCommentAuthor.__typename": (v58/*: any*/),
        "node.deletedCommentAuthor.id": (v61/*: any*/),
        "node.deletedCommentAuthor.login": (v58/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v61/*: any*/),
        "node.discussion.number": (v67/*: any*/),
        "node.discussion.url": (v60/*: any*/),
        "node.duplicateOf": (v66/*: any*/),
        "node.duplicateOf.__isNode": (v58/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v58/*: any*/),
        "node.duplicateOf.__typename": (v58/*: any*/),
        "node.duplicateOf.id": (v61/*: any*/),
        "node.duplicateOf.isDraft": (v62/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v62/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v58/*: any*/),
        "node.duplicateOf.number": (v67/*: any*/),
        "node.duplicateOf.pullTitleHTML": (v65/*: any*/),
        "node.duplicateOf.repository": (v68/*: any*/),
        "node.duplicateOf.repository.id": (v61/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v62/*: any*/),
        "node.duplicateOf.repository.name": (v58/*: any*/),
        "node.duplicateOf.repository.owner": (v69/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v58/*: any*/),
        "node.duplicateOf.repository.owner.id": (v61/*: any*/),
        "node.duplicateOf.repository.owner.login": (v58/*: any*/),
        "node.duplicateOf.state": (v70/*: any*/),
        "node.duplicateOf.stateReason": (v71/*: any*/),
        "node.duplicateOf.url": (v60/*: any*/),
        "node.fromRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.fromRepository.id": (v61/*: any*/),
        "node.fromRepository.nameWithOwner": (v58/*: any*/),
        "node.fromRepository.url": (v60/*: any*/),
        "node.id": (v61/*: any*/),
        "node.innerSource": (v75/*: any*/),
        "node.innerSource.__isNode": (v58/*: any*/),
        "node.innerSource.__isReferencedSubject": (v58/*: any*/),
        "node.innerSource.__typename": (v58/*: any*/),
        "node.innerSource.id": (v61/*: any*/),
        "node.innerSource.isDraft": (v62/*: any*/),
        "node.innerSource.isInMergeQueue": (v62/*: any*/),
        "node.innerSource.issueTitleHTML": (v58/*: any*/),
        "node.innerSource.number": (v67/*: any*/),
        "node.innerSource.pullTitleHTML": (v65/*: any*/),
        "node.innerSource.repository": (v68/*: any*/),
        "node.innerSource.repository.id": (v61/*: any*/),
        "node.innerSource.repository.isPrivate": (v62/*: any*/),
        "node.innerSource.repository.name": (v58/*: any*/),
        "node.innerSource.repository.owner": (v69/*: any*/),
        "node.innerSource.repository.owner.__typename": (v58/*: any*/),
        "node.innerSource.repository.owner.id": (v61/*: any*/),
        "node.innerSource.repository.owner.login": (v58/*: any*/),
        "node.innerSource.state": (v70/*: any*/),
        "node.innerSource.stateReason": (v71/*: any*/),
        "node.innerSource.url": (v60/*: any*/),
        "node.isCanonicalOfClosedDuplicate": (v76/*: any*/),
        "node.isHidden": (v62/*: any*/),
        "node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "node.issue.author": (v59/*: any*/),
        "node.issue.author.__typename": (v58/*: any*/),
        "node.issue.author.id": (v61/*: any*/),
        "node.issue.author.login": (v58/*: any*/),
        "node.issue.databaseId": (v74/*: any*/),
        "node.issue.id": (v61/*: any*/),
        "node.issue.locked": (v62/*: any*/),
        "node.issue.number": (v67/*: any*/),
        "node.issueType": (v77/*: any*/),
        "node.issueType.color": (v78/*: any*/),
        "node.issueType.id": (v61/*: any*/),
        "node.issueType.name": (v58/*: any*/),
        "node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "node.label.color": (v58/*: any*/),
        "node.label.description": (v72/*: any*/),
        "node.label.id": (v61/*: any*/),
        "node.label.name": (v58/*: any*/),
        "node.label.nameHTML": (v58/*: any*/),
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
        "node.lastUserContentEdit.editor": (v59/*: any*/),
        "node.lastUserContentEdit.editor.__typename": (v58/*: any*/),
        "node.lastUserContentEdit.editor.id": (v61/*: any*/),
        "node.lastUserContentEdit.editor.login": (v58/*: any*/),
        "node.lastUserContentEdit.editor.url": (v60/*: any*/),
        "node.lastUserContentEdit.id": (v61/*: any*/),
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
        "node.milestone.id": (v61/*: any*/),
        "node.milestone.url": (v60/*: any*/),
        "node.milestoneTitle": (v58/*: any*/),
        "node.minimizedReason": (v72/*: any*/),
        "node.parent": (v79/*: any*/),
        "node.parent.__isReferencedSubject": (v58/*: any*/),
        "node.parent.__typename": (v58/*: any*/),
        "node.parent.databaseId": (v74/*: any*/),
        "node.parent.id": (v61/*: any*/),
        "node.parent.isDraft": (v62/*: any*/),
        "node.parent.isInMergeQueue": (v62/*: any*/),
        "node.parent.issueTitleHTML": (v58/*: any*/),
        "node.parent.number": (v67/*: any*/),
        "node.parent.pullTitleHTML": (v65/*: any*/),
        "node.parent.repository": (v68/*: any*/),
        "node.parent.repository.id": (v61/*: any*/),
        "node.parent.repository.isPrivate": (v62/*: any*/),
        "node.parent.repository.name": (v58/*: any*/),
        "node.parent.repository.owner": (v69/*: any*/),
        "node.parent.repository.owner.__typename": (v58/*: any*/),
        "node.parent.repository.owner.id": (v61/*: any*/),
        "node.parent.repository.owner.login": (v58/*: any*/),
        "node.parent.state": (v70/*: any*/),
        "node.parent.stateReason": (v71/*: any*/),
        "node.parent.url": (v60/*: any*/),
        "node.pendingBlock": (v76/*: any*/),
        "node.pendingMinimizeReason": (v72/*: any*/),
        "node.pendingUnblock": (v76/*: any*/),
        "node.pendingUndo": (v76/*: any*/),
        "node.prevIssueType": (v77/*: any*/),
        "node.prevIssueType.color": (v78/*: any*/),
        "node.prevIssueType.id": (v61/*: any*/),
        "node.prevIssueType.name": (v58/*: any*/),
        "node.previousStatus": (v58/*: any*/),
        "node.previousTitle": (v58/*: any*/),
        "node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.project.id": (v61/*: any*/),
        "node.project.title": (v58/*: any*/),
        "node.project.url": (v60/*: any*/),
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
        "node.reactionGroups.reactors.nodes.__isNode": (v58/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v58/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v61/*: any*/),
        "node.reactionGroups.reactors.nodes.isCopilot": (v62/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v58/*: any*/),
        "node.reactionGroups.reactors.totalCount": (v67/*: any*/),
        "node.reactionGroups.viewerHasReacted": (v62/*: any*/),
        "node.referencedAt": (v63/*: any*/),
        "node.repository": (v68/*: any*/),
        "node.repository.databaseId": (v74/*: any*/),
        "node.repository.id": (v61/*: any*/),
        "node.repository.isPrivate": (v62/*: any*/),
        "node.repository.name": (v58/*: any*/),
        "node.repository.nameWithOwner": (v58/*: any*/),
        "node.repository.owner": (v69/*: any*/),
        "node.repository.owner.__typename": (v58/*: any*/),
        "node.repository.owner.id": (v61/*: any*/),
        "node.repository.owner.login": (v58/*: any*/),
        "node.repository.owner.url": (v60/*: any*/),
        "node.repository.slashCommandsEnabled": (v62/*: any*/),
        "node.showSpammyBadge": (v62/*: any*/),
        "node.stateReason": (v71/*: any*/),
        "node.status": (v58/*: any*/),
        "node.subIssue": (v79/*: any*/),
        "node.subIssue.__isReferencedSubject": (v58/*: any*/),
        "node.subIssue.__typename": (v58/*: any*/),
        "node.subIssue.databaseId": (v74/*: any*/),
        "node.subIssue.id": (v61/*: any*/),
        "node.subIssue.isDraft": (v62/*: any*/),
        "node.subIssue.isInMergeQueue": (v62/*: any*/),
        "node.subIssue.issueTitleHTML": (v58/*: any*/),
        "node.subIssue.number": (v67/*: any*/),
        "node.subIssue.pullTitleHTML": (v65/*: any*/),
        "node.subIssue.repository": (v68/*: any*/),
        "node.subIssue.repository.id": (v61/*: any*/),
        "node.subIssue.repository.isPrivate": (v62/*: any*/),
        "node.subIssue.repository.name": (v58/*: any*/),
        "node.subIssue.repository.owner": (v69/*: any*/),
        "node.subIssue.repository.owner.__typename": (v58/*: any*/),
        "node.subIssue.repository.owner.id": (v61/*: any*/),
        "node.subIssue.repository.owner.login": (v58/*: any*/),
        "node.subIssue.state": (v70/*: any*/),
        "node.subIssue.stateReason": (v71/*: any*/),
        "node.subIssue.url": (v60/*: any*/),
        "node.subject": (v75/*: any*/),
        "node.subject.__isNode": (v58/*: any*/),
        "node.subject.__typename": (v58/*: any*/),
        "node.subject.id": (v61/*: any*/),
        "node.subject.isDraft": (v62/*: any*/),
        "node.subject.isInMergeQueue": (v62/*: any*/),
        "node.subject.number": (v67/*: any*/),
        "node.subject.repository": (v68/*: any*/),
        "node.subject.repository.id": (v61/*: any*/),
        "node.subject.repository.name": (v58/*: any*/),
        "node.subject.repository.owner": (v69/*: any*/),
        "node.subject.repository.owner.__typename": (v58/*: any*/),
        "node.subject.repository.owner.id": (v61/*: any*/),
        "node.subject.repository.owner.login": (v58/*: any*/),
        "node.subject.state": (v70/*: any*/),
        "node.subject.title": (v58/*: any*/),
        "node.subject.url": (v60/*: any*/),
        "node.target": (v75/*: any*/),
        "node.target.__isNode": (v58/*: any*/),
        "node.target.__typename": (v58/*: any*/),
        "node.target.id": (v61/*: any*/),
        "node.target.repository": (v68/*: any*/),
        "node.target.repository.id": (v61/*: any*/),
        "node.url": (v60/*: any*/),
        "node.viewerCanBlockFromOrg": (v62/*: any*/),
        "node.viewerCanDelete": (v62/*: any*/),
        "node.viewerCanMinimize": (v62/*: any*/),
        "node.viewerCanReadUserContentEdits": (v62/*: any*/),
        "node.viewerCanReport": (v62/*: any*/),
        "node.viewerCanReportToMaintainer": (v62/*: any*/),
        "node.viewerCanUnblockFromOrg": (v62/*: any*/),
        "node.viewerCanUndo": (v62/*: any*/),
        "node.viewerCanUpdate": (v62/*: any*/),
        "node.viewerDidAuthor": (v62/*: any*/),
        "node.willCloseSubject": (v62/*: any*/),
        "node.willCloseTarget": (v62/*: any*/)
      }
    },
    "name": "IssueEventWrapperQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "9da1888668dc90ad94945ea6278d2d5a";

export default node;
