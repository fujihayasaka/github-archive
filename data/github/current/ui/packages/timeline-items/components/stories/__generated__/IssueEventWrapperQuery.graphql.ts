/**
 * @generated SignedSource<<5cb43bf2be7e3f95b40d6bf4fcaf08fc>>
 * @relayHash 80ee3d6ee6351c75001da4dbd5bb74a2
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 80ee3d6ee6351c75001da4dbd5bb74a2

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
  "kind": "InlineFragment",
  "selections": (v13/*: any*/),
  "type": "User",
  "abstractKey": null
},
v15 = {
  "kind": "InlineFragment",
  "selections": (v13/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v16 = {
  "kind": "InlineFragment",
  "selections": (v13/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v17 = {
  "kind": "InlineFragment",
  "selections": (v13/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v18 = [
  (v2/*: any*/)
],
v19 = {
  "kind": "InlineFragment",
  "selections": (v18/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v20 = {
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
                (v14/*: any*/),
                (v15/*: any*/),
                (v16/*: any*/),
                (v17/*: any*/),
                (v19/*: any*/)
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
v21 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v22 = {
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
v23 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v1/*: any*/),
    (v21/*: any*/),
    (v22/*: any*/),
    (v6/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v24 = [
  (v5/*: any*/),
  (v3/*: any*/),
  (v23/*: any*/)
],
v25 = {
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
v26 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v12/*: any*/),
  "storageKey": null
},
v28 = {
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
    (v27/*: any*/)
  ],
  "storageKey": null
},
v29 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v26/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v25/*: any*/),
    (v28/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v30 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
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
  "name": "isInMergeQueue",
  "storageKey": null
},
v34 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v30/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v31/*: any*/),
    (v32/*: any*/),
    (v33/*: any*/),
    (v28/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v35 = {
  "kind": "InlineFragment",
  "selections": [
    (v29/*: any*/),
    (v34/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v27/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v39 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v23/*: any*/)
],
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v41 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v23/*: any*/),
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
      (v40/*: any*/),
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
v42 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v23/*: any*/),
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
v43 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v18/*: any*/),
  "storageKey": null
},
v44 = [
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
v45 = [
  (v3/*: any*/),
  (v23/*: any*/),
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
          (v36/*: any*/),
          (v4/*: any*/),
          (v11/*: any*/),
          (v31/*: any*/),
          (v32/*: any*/),
          (v33/*: any*/),
          (v37/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v19/*: any*/)
    ],
    "storageKey": null
  }
],
v46 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v26/*: any*/),
        (v4/*: any*/),
        (v25/*: any*/),
        (v28/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v30/*: any*/),
        (v4/*: any*/),
        (v31/*: any*/),
        (v32/*: any*/),
        (v33/*: any*/),
        (v28/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v48 = [
  (v35/*: any*/)
],
v49 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v36/*: any*/),
    (v4/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v9/*: any*/),
    (v27/*: any*/)
  ],
  "storageKey": null
},
v51 = [
  (v43/*: any*/),
  (v3/*: any*/),
  (v2/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      (v1/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v26/*: any*/),
          (v4/*: any*/),
          (v11/*: any*/),
          (v25/*: any*/),
          (v50/*: any*/)
        ],
        "type": "Issue",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": [
          (v30/*: any*/),
          (v4/*: any*/),
          (v11/*: any*/),
          (v31/*: any*/),
          (v32/*: any*/),
          (v33/*: any*/),
          (v50/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      }
    ],
    "type": "ReferencedSubject",
    "abstractKey": "__isReferencedSubject"
  }
],
v52 = [
  (v3/*: any*/),
  (v23/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": (v51/*: any*/),
    "storageKey": null
  }
],
v53 = [
  (v3/*: any*/),
  (v23/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": (v51/*: any*/),
    "storageKey": null
  }
],
v54 = [
  (v8/*: any*/),
  (v40/*: any*/),
  (v2/*: any*/)
],
v55 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v54/*: any*/),
  "storageKey": null
},
v56 = [
  (v3/*: any*/),
  (v23/*: any*/),
  (v5/*: any*/),
  (v55/*: any*/)
],
v57 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v58 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v59 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v61 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v62 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v63 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v64 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v65 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v66 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v67 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v68 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v69 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v70 = {
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
v71 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v72 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v73 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v74 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v75 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v76 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v77 = {
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
v78 = {
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
              (v20/*: any*/)
            ],
            "type": "IssueComment",
            "abstractKey": null
          },
          (v20/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": (v24/*: any*/),
            "type": "SubscribedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v24/*: any*/),
            "type": "UnsubscribedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v24/*: any*/),
            "type": "MentionedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v25/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  (v35/*: any*/),
                  (v19/*: any*/)
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
                      (v36/*: any*/)
                    ],
                    "type": "ProjectV2",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v11/*: any*/),
                      (v37/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v38/*: any*/),
                      (v37/*: any*/)
                    ],
                    "type": "Commit",
                    "abstractKey": null
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v23/*: any*/)
            ],
            "type": "ClosedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v39/*: any*/),
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
              (v23/*: any*/)
            ],
            "type": "LockedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v39/*: any*/),
            "type": "UnlockedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v39/*: any*/),
            "type": "PinnedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v39/*: any*/),
            "type": "UnpinnedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v41/*: any*/),
            "type": "LabeledEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v23/*: any*/),
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
            "selections": (v41/*: any*/),
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
                  (v21/*: any*/),
                  (v22/*: any*/),
                  (v2/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "assignee",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  (v14/*: any*/),
                  (v17/*: any*/),
                  (v16/*: any*/),
                  (v15/*: any*/),
                  (v19/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "type": "UnassignedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v23/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "assignee",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  (v14/*: any*/),
                  (v17/*: any*/),
                  (v16/*: any*/),
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v6/*: any*/),
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
                  (v19/*: any*/)
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
              (v3/*: any*/),
              (v5/*: any*/),
              (v23/*: any*/),
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
              (v23/*: any*/),
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
            "selections": (v42/*: any*/),
            "type": "MilestonedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v42/*: any*/),
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
                      (v43/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  (v19/*: any*/)
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
                  (v29/*: any*/),
                  (v34/*: any*/),
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v23/*: any*/)
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
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v23/*: any*/),
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
                  (v38/*: any*/),
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
                      (v31/*: any*/),
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
                            "selections": (v44/*: any*/),
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "CertificateAttributes",
                            "kind": "LinkedField",
                            "name": "subject",
                            "plural": false,
                            "selections": (v44/*: any*/),
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
                      (v27/*: any*/),
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
            "selections": (v45/*: any*/),
            "type": "ConnectedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v23/*: any*/),
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
            "selections": (v45/*: any*/),
            "type": "DisconnectedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v23/*: any*/),
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
                      (v46/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v11/*: any*/),
                      (v2/*: any*/),
                      (v46/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v47/*: any*/),
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
              (v23/*: any*/),
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
                    "selections": (v48/*: any*/),
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v48/*: any*/),
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v47/*: any*/),
              (v3/*: any*/)
            ],
            "type": "UnmarkedAsDuplicateEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v23/*: any*/),
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
              (v23/*: any*/),
              (v49/*: any*/)
            ],
            "type": "AddedToProjectV2Event",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v23/*: any*/),
              (v49/*: any*/)
            ],
            "type": "RemovedFromProjectV2Event",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v23/*: any*/),
              (v49/*: any*/),
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
              (v23/*: any*/),
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
            "selections": (v53/*: any*/),
            "type": "ParentIssueAddedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v53/*: any*/),
            "type": "ParentIssueRemovedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v56/*: any*/),
            "type": "IssueTypeAddedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v56/*: any*/),
            "type": "IssueTypeRemovedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v23/*: any*/),
              (v5/*: any*/),
              (v55/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "prevIssueType",
                "plural": false,
                "selections": (v54/*: any*/),
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
    "id": "80ee3d6ee6351c75001da4dbd5bb74a2",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isComment": (v57/*: any*/),
        "node.__isReactable": (v57/*: any*/),
        "node.__typename": (v57/*: any*/),
        "node.actor": (v58/*: any*/),
        "node.actor.__isActor": (v57/*: any*/),
        "node.actor.__typename": (v57/*: any*/),
        "node.actor.avatarUrl": (v59/*: any*/),
        "node.actor.id": (v60/*: any*/),
        "node.actor.login": (v57/*: any*/),
        "node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "node.assignee.__isNode": (v57/*: any*/),
        "node.assignee.__typename": (v57/*: any*/),
        "node.assignee.id": (v60/*: any*/),
        "node.assignee.isCopilot": (v61/*: any*/),
        "node.assignee.login": (v57/*: any*/),
        "node.author": (v58/*: any*/),
        "node.author.__typename": (v57/*: any*/),
        "node.author.avatarUrl": (v59/*: any*/),
        "node.author.id": (v60/*: any*/),
        "node.author.login": (v57/*: any*/),
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
        "node.authorToRepoOwnerSponsorship.id": (v60/*: any*/),
        "node.authorToRepoOwnerSponsorship.isActive": (v61/*: any*/),
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
        "node.blockedUser": (v63/*: any*/),
        "node.blockedUser.id": (v60/*: any*/),
        "node.blockedUser.login": (v57/*: any*/),
        "node.body": (v57/*: any*/),
        "node.bodyHTML": (v64/*: any*/),
        "node.bodyVersion": (v57/*: any*/),
        "node.canonical": (v65/*: any*/),
        "node.canonical.__isNode": (v57/*: any*/),
        "node.canonical.__isReferencedSubject": (v57/*: any*/),
        "node.canonical.__typename": (v57/*: any*/),
        "node.canonical.id": (v60/*: any*/),
        "node.canonical.isDraft": (v61/*: any*/),
        "node.canonical.isInMergeQueue": (v61/*: any*/),
        "node.canonical.issueTitleHTML": (v57/*: any*/),
        "node.canonical.number": (v66/*: any*/),
        "node.canonical.pullTitleHTML": (v64/*: any*/),
        "node.canonical.repository": (v67/*: any*/),
        "node.canonical.repository.id": (v60/*: any*/),
        "node.canonical.repository.isPrivate": (v61/*: any*/),
        "node.canonical.repository.name": (v57/*: any*/),
        "node.canonical.repository.owner": (v68/*: any*/),
        "node.canonical.repository.owner.__typename": (v57/*: any*/),
        "node.canonical.repository.owner.id": (v60/*: any*/),
        "node.canonical.repository.owner.login": (v57/*: any*/),
        "node.canonical.state": (v69/*: any*/),
        "node.canonical.stateReason": (v70/*: any*/),
        "node.canonical.url": (v59/*: any*/),
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v57/*: any*/),
        "node.closer.__typename": (v57/*: any*/),
        "node.closer.abbreviatedOid": (v57/*: any*/),
        "node.closer.id": (v60/*: any*/),
        "node.closer.number": (v66/*: any*/),
        "node.closer.repository": (v67/*: any*/),
        "node.closer.repository.id": (v60/*: any*/),
        "node.closer.repository.name": (v57/*: any*/),
        "node.closer.repository.owner": (v68/*: any*/),
        "node.closer.repository.owner.__typename": (v57/*: any*/),
        "node.closer.repository.owner.id": (v60/*: any*/),
        "node.closer.repository.owner.login": (v57/*: any*/),
        "node.closer.title": (v57/*: any*/),
        "node.closer.url": (v59/*: any*/),
        "node.closingProjectItemStatus": (v71/*: any*/),
        "node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "node.commit.abbreviatedOid": (v57/*: any*/),
        "node.commit.hasSignature": (v61/*: any*/),
        "node.commit.id": (v60/*: any*/),
        "node.commit.message": (v57/*: any*/),
        "node.commit.messageBodyHTML": (v64/*: any*/),
        "node.commit.messageHeadlineHTML": (v64/*: any*/),
        "node.commit.repository": (v67/*: any*/),
        "node.commit.repository.defaultBranch": (v57/*: any*/),
        "node.commit.repository.id": (v60/*: any*/),
        "node.commit.repository.name": (v57/*: any*/),
        "node.commit.repository.owner": (v68/*: any*/),
        "node.commit.repository.owner.__typename": (v57/*: any*/),
        "node.commit.repository.owner.id": (v60/*: any*/),
        "node.commit.repository.owner.login": (v57/*: any*/),
        "node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "node.commit.signature.__typename": (v57/*: any*/),
        "node.commit.signature.issuer": (v72/*: any*/),
        "node.commit.signature.issuer.commonName": (v71/*: any*/),
        "node.commit.signature.issuer.emailAddress": (v71/*: any*/),
        "node.commit.signature.issuer.organization": (v71/*: any*/),
        "node.commit.signature.issuer.organizationUnit": (v71/*: any*/),
        "node.commit.signature.keyFingerprint": (v71/*: any*/),
        "node.commit.signature.keyId": (v71/*: any*/),
        "node.commit.signature.signer": (v63/*: any*/),
        "node.commit.signature.signer.avatarUrl": (v59/*: any*/),
        "node.commit.signature.signer.id": (v60/*: any*/),
        "node.commit.signature.signer.login": (v57/*: any*/),
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
        "node.commit.signature.subject": (v72/*: any*/),
        "node.commit.signature.subject.commonName": (v71/*: any*/),
        "node.commit.signature.subject.emailAddress": (v71/*: any*/),
        "node.commit.signature.subject.organization": (v71/*: any*/),
        "node.commit.signature.subject.organizationUnit": (v71/*: any*/),
        "node.commit.signature.wasSignedByGitHub": (v61/*: any*/),
        "node.commit.url": (v59/*: any*/),
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
        "node.createdViaEmail": (v61/*: any*/),
        "node.currentTitle": (v57/*: any*/),
        "node.databaseId": (v73/*: any*/),
        "node.deletedCommentAuthor": (v58/*: any*/),
        "node.deletedCommentAuthor.__typename": (v57/*: any*/),
        "node.deletedCommentAuthor.id": (v60/*: any*/),
        "node.deletedCommentAuthor.login": (v57/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v60/*: any*/),
        "node.discussion.number": (v66/*: any*/),
        "node.discussion.url": (v59/*: any*/),
        "node.duplicateOf": (v65/*: any*/),
        "node.duplicateOf.__isNode": (v57/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v57/*: any*/),
        "node.duplicateOf.__typename": (v57/*: any*/),
        "node.duplicateOf.id": (v60/*: any*/),
        "node.duplicateOf.isDraft": (v61/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v61/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v57/*: any*/),
        "node.duplicateOf.number": (v66/*: any*/),
        "node.duplicateOf.pullTitleHTML": (v64/*: any*/),
        "node.duplicateOf.repository": (v67/*: any*/),
        "node.duplicateOf.repository.id": (v60/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v61/*: any*/),
        "node.duplicateOf.repository.name": (v57/*: any*/),
        "node.duplicateOf.repository.owner": (v68/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v57/*: any*/),
        "node.duplicateOf.repository.owner.id": (v60/*: any*/),
        "node.duplicateOf.repository.owner.login": (v57/*: any*/),
        "node.duplicateOf.state": (v69/*: any*/),
        "node.duplicateOf.stateReason": (v70/*: any*/),
        "node.duplicateOf.url": (v59/*: any*/),
        "node.fromRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.fromRepository.id": (v60/*: any*/),
        "node.fromRepository.nameWithOwner": (v57/*: any*/),
        "node.fromRepository.url": (v59/*: any*/),
        "node.id": (v60/*: any*/),
        "node.innerSource": (v74/*: any*/),
        "node.innerSource.__isNode": (v57/*: any*/),
        "node.innerSource.__isReferencedSubject": (v57/*: any*/),
        "node.innerSource.__typename": (v57/*: any*/),
        "node.innerSource.id": (v60/*: any*/),
        "node.innerSource.isDraft": (v61/*: any*/),
        "node.innerSource.isInMergeQueue": (v61/*: any*/),
        "node.innerSource.issueTitleHTML": (v57/*: any*/),
        "node.innerSource.number": (v66/*: any*/),
        "node.innerSource.pullTitleHTML": (v64/*: any*/),
        "node.innerSource.repository": (v67/*: any*/),
        "node.innerSource.repository.id": (v60/*: any*/),
        "node.innerSource.repository.isPrivate": (v61/*: any*/),
        "node.innerSource.repository.name": (v57/*: any*/),
        "node.innerSource.repository.owner": (v68/*: any*/),
        "node.innerSource.repository.owner.__typename": (v57/*: any*/),
        "node.innerSource.repository.owner.id": (v60/*: any*/),
        "node.innerSource.repository.owner.login": (v57/*: any*/),
        "node.innerSource.state": (v69/*: any*/),
        "node.innerSource.stateReason": (v70/*: any*/),
        "node.innerSource.url": (v59/*: any*/),
        "node.isCanonicalOfClosedDuplicate": (v75/*: any*/),
        "node.isHidden": (v61/*: any*/),
        "node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "node.issue.author": (v58/*: any*/),
        "node.issue.author.__typename": (v57/*: any*/),
        "node.issue.author.id": (v60/*: any*/),
        "node.issue.author.login": (v57/*: any*/),
        "node.issue.databaseId": (v73/*: any*/),
        "node.issue.id": (v60/*: any*/),
        "node.issue.locked": (v61/*: any*/),
        "node.issue.number": (v66/*: any*/),
        "node.issueType": (v76/*: any*/),
        "node.issueType.color": (v77/*: any*/),
        "node.issueType.id": (v60/*: any*/),
        "node.issueType.name": (v57/*: any*/),
        "node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "node.label.color": (v57/*: any*/),
        "node.label.description": (v71/*: any*/),
        "node.label.id": (v60/*: any*/),
        "node.label.name": (v57/*: any*/),
        "node.label.nameHTML": (v57/*: any*/),
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
        "node.lastUserContentEdit.editor": (v58/*: any*/),
        "node.lastUserContentEdit.editor.__typename": (v57/*: any*/),
        "node.lastUserContentEdit.editor.id": (v60/*: any*/),
        "node.lastUserContentEdit.editor.login": (v57/*: any*/),
        "node.lastUserContentEdit.editor.url": (v59/*: any*/),
        "node.lastUserContentEdit.id": (v60/*: any*/),
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
        "node.milestone.id": (v60/*: any*/),
        "node.milestone.url": (v59/*: any*/),
        "node.milestoneTitle": (v57/*: any*/),
        "node.minimizedReason": (v71/*: any*/),
        "node.parent": (v78/*: any*/),
        "node.parent.__isReferencedSubject": (v57/*: any*/),
        "node.parent.__typename": (v57/*: any*/),
        "node.parent.databaseId": (v73/*: any*/),
        "node.parent.id": (v60/*: any*/),
        "node.parent.isDraft": (v61/*: any*/),
        "node.parent.isInMergeQueue": (v61/*: any*/),
        "node.parent.issueTitleHTML": (v57/*: any*/),
        "node.parent.number": (v66/*: any*/),
        "node.parent.pullTitleHTML": (v64/*: any*/),
        "node.parent.repository": (v67/*: any*/),
        "node.parent.repository.id": (v60/*: any*/),
        "node.parent.repository.isPrivate": (v61/*: any*/),
        "node.parent.repository.name": (v57/*: any*/),
        "node.parent.repository.owner": (v68/*: any*/),
        "node.parent.repository.owner.__typename": (v57/*: any*/),
        "node.parent.repository.owner.id": (v60/*: any*/),
        "node.parent.repository.owner.login": (v57/*: any*/),
        "node.parent.state": (v69/*: any*/),
        "node.parent.stateReason": (v70/*: any*/),
        "node.parent.url": (v59/*: any*/),
        "node.pendingBlock": (v75/*: any*/),
        "node.pendingMinimizeReason": (v71/*: any*/),
        "node.pendingUnblock": (v75/*: any*/),
        "node.pendingUndo": (v75/*: any*/),
        "node.prevIssueType": (v76/*: any*/),
        "node.prevIssueType.color": (v77/*: any*/),
        "node.prevIssueType.id": (v60/*: any*/),
        "node.prevIssueType.name": (v57/*: any*/),
        "node.previousStatus": (v57/*: any*/),
        "node.previousTitle": (v57/*: any*/),
        "node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.project.id": (v60/*: any*/),
        "node.project.title": (v57/*: any*/),
        "node.project.url": (v59/*: any*/),
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
        "node.reactionGroups.reactors.nodes.__isNode": (v57/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v57/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v60/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v57/*: any*/),
        "node.reactionGroups.reactors.totalCount": (v66/*: any*/),
        "node.reactionGroups.viewerHasReacted": (v61/*: any*/),
        "node.referencedAt": (v62/*: any*/),
        "node.repository": (v67/*: any*/),
        "node.repository.databaseId": (v73/*: any*/),
        "node.repository.id": (v60/*: any*/),
        "node.repository.isPrivate": (v61/*: any*/),
        "node.repository.name": (v57/*: any*/),
        "node.repository.nameWithOwner": (v57/*: any*/),
        "node.repository.owner": (v68/*: any*/),
        "node.repository.owner.__typename": (v57/*: any*/),
        "node.repository.owner.id": (v60/*: any*/),
        "node.repository.owner.login": (v57/*: any*/),
        "node.repository.owner.url": (v59/*: any*/),
        "node.repository.slashCommandsEnabled": (v61/*: any*/),
        "node.showSpammyBadge": (v61/*: any*/),
        "node.stateReason": (v70/*: any*/),
        "node.status": (v57/*: any*/),
        "node.subIssue": (v78/*: any*/),
        "node.subIssue.__isReferencedSubject": (v57/*: any*/),
        "node.subIssue.__typename": (v57/*: any*/),
        "node.subIssue.databaseId": (v73/*: any*/),
        "node.subIssue.id": (v60/*: any*/),
        "node.subIssue.isDraft": (v61/*: any*/),
        "node.subIssue.isInMergeQueue": (v61/*: any*/),
        "node.subIssue.issueTitleHTML": (v57/*: any*/),
        "node.subIssue.number": (v66/*: any*/),
        "node.subIssue.pullTitleHTML": (v64/*: any*/),
        "node.subIssue.repository": (v67/*: any*/),
        "node.subIssue.repository.id": (v60/*: any*/),
        "node.subIssue.repository.isPrivate": (v61/*: any*/),
        "node.subIssue.repository.name": (v57/*: any*/),
        "node.subIssue.repository.owner": (v68/*: any*/),
        "node.subIssue.repository.owner.__typename": (v57/*: any*/),
        "node.subIssue.repository.owner.id": (v60/*: any*/),
        "node.subIssue.repository.owner.login": (v57/*: any*/),
        "node.subIssue.state": (v69/*: any*/),
        "node.subIssue.stateReason": (v70/*: any*/),
        "node.subIssue.url": (v59/*: any*/),
        "node.subject": (v74/*: any*/),
        "node.subject.__isNode": (v57/*: any*/),
        "node.subject.__typename": (v57/*: any*/),
        "node.subject.id": (v60/*: any*/),
        "node.subject.isDraft": (v61/*: any*/),
        "node.subject.isInMergeQueue": (v61/*: any*/),
        "node.subject.number": (v66/*: any*/),
        "node.subject.repository": (v67/*: any*/),
        "node.subject.repository.id": (v60/*: any*/),
        "node.subject.repository.name": (v57/*: any*/),
        "node.subject.repository.owner": (v68/*: any*/),
        "node.subject.repository.owner.__typename": (v57/*: any*/),
        "node.subject.repository.owner.id": (v60/*: any*/),
        "node.subject.repository.owner.login": (v57/*: any*/),
        "node.subject.state": (v69/*: any*/),
        "node.subject.title": (v57/*: any*/),
        "node.subject.url": (v59/*: any*/),
        "node.target": (v74/*: any*/),
        "node.target.__isNode": (v57/*: any*/),
        "node.target.__typename": (v57/*: any*/),
        "node.target.id": (v60/*: any*/),
        "node.target.repository": (v67/*: any*/),
        "node.target.repository.id": (v60/*: any*/),
        "node.url": (v59/*: any*/),
        "node.viewerCanBlockFromOrg": (v61/*: any*/),
        "node.viewerCanDelete": (v61/*: any*/),
        "node.viewerCanMinimize": (v61/*: any*/),
        "node.viewerCanReadUserContentEdits": (v61/*: any*/),
        "node.viewerCanReport": (v61/*: any*/),
        "node.viewerCanReportToMaintainer": (v61/*: any*/),
        "node.viewerCanUnblockFromOrg": (v61/*: any*/),
        "node.viewerCanUndo": (v61/*: any*/),
        "node.viewerCanUpdate": (v61/*: any*/),
        "node.viewerDidAuthor": (v61/*: any*/),
        "node.willCloseSubject": (v61/*: any*/),
        "node.willCloseTarget": (v61/*: any*/)
      }
    },
    "name": "IssueEventWrapperQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "c6ca4eca2e3fc4b391797b44faef3120";

export default node;
