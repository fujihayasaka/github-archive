/**
 * @generated SignedSource<<eabfdaa3e1e59653f31e0f82d4ff5c2d>>
 * @relayHash 2eccf126a9af0c2217f6b38b81deae1d
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2eccf126a9af0c2217f6b38b81deae1d

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueEventWrapperQuery$variables = Record<PropertyKey, never>;
export type IssueEventWrapperQuery$data = {
  readonly node: {
    readonly __typename: string;
    readonly " $fragmentSpreads": FragmentRefs<"AddedToProjectEvent" | "AddedToProjectV2Event" | "AssignedEvent" | "ClosedEvent" | "CommentDeletedEvent" | "ConnectedEvent" | "ConvertedFromDraftEvent" | "ConvertedNoteToIssueEvent" | "ConvertedToDiscussionEvent" | "CrossReferencedEvent" | "DemilestonedEvent" | "DisconnectedEvent" | "IssueComment_issueComment" | "LabeledEvent" | "LockedEvent" | "MarkedAsDuplicateEvent" | "MentionedEvent" | "MilestonedEvent" | "MovedColumnsInProjectEvent" | "PinnedEvent" | "ProjectV2ItemStatusChangedEvent" | "ReactionViewerRelayGroups" | "ReferencedEvent" | "RemovedFromProjectEvent" | "RemovedFromProjectV2Event" | "RenamedTitleEvent" | "ReopenedEvent" | "SubscribedEvent" | "TransferredEvent" | "UnassignedEvent" | "UnlabeledEvent" | "UnlockedEvent" | "UnmarkedAsDuplicateEvent" | "UnpinnedEvent" | "UnsubscribedEvent" | "UserBlockedEvent">;
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
v24 = {
  "alias": null,
  "args": null,
  "concreteType": "Project",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v4/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "projectColumnName",
  "storageKey": null
},
v26 = [
  (v5/*: any*/),
  (v3/*: any*/),
  (v23/*: any*/)
],
v27 = {
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
v28 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v12/*: any*/),
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
    (v2/*: any*/),
    (v8/*: any*/),
    (v9/*: any*/),
    (v29/*: any*/)
  ],
  "storageKey": null
},
v31 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/),
    (v28/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v27/*: any*/),
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
    (v2/*: any*/),
    (v32/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v33/*: any*/),
    (v34/*: any*/),
    (v35/*: any*/),
    (v30/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v37 = {
  "kind": "InlineFragment",
  "selections": [
    (v31/*: any*/),
    (v36/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v38 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v39 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v29/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v41 = [
  (v3/*: any*/),
  (v5/*: any*/),
  (v23/*: any*/)
],
v42 = [
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
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "color",
        "storageKey": null
      },
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
v43 = {
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
},
v44 = [
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
v45 = [
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
v46 = [
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
          (v38/*: any*/),
          (v4/*: any*/),
          (v11/*: any*/),
          (v33/*: any*/),
          (v34/*: any*/),
          (v35/*: any*/),
          (v39/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v19/*: any*/)
    ],
    "storageKey": null
  }
],
v47 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v28/*: any*/),
        (v4/*: any*/),
        (v27/*: any*/),
        (v30/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v32/*: any*/),
        (v4/*: any*/),
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
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v49 = [
  (v37/*: any*/)
],
v50 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v38/*: any*/),
    (v4/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v51 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v52 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v53 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v54 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v55 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v56 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v57 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "HTML"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueOrPullRequest"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v61 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v62 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v63 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v64 = {
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
v65 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v66 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "CertificateAttributes"
},
v67 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v68 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ReferencedSubject"
},
v69 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
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
            "selections": [
              (v5/*: any*/),
              (v23/*: any*/),
              (v24/*: any*/),
              (v25/*: any*/),
              (v3/*: any*/)
            ],
            "type": "AddedToProjectEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v3/*: any*/),
              (v23/*: any*/),
              (v24/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "previousProjectColumnName",
                "storageKey": null
              },
              (v25/*: any*/)
            ],
            "type": "MovedColumnsInProjectEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v3/*: any*/),
              (v23/*: any*/),
              (v24/*: any*/),
              (v25/*: any*/)
            ],
            "type": "RemovedFromProjectEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v26/*: any*/),
            "type": "SubscribedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v26/*: any*/),
            "type": "UnsubscribedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v26/*: any*/),
            "type": "MentionedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v5/*: any*/),
              (v27/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "duplicateOf",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  (v37/*: any*/),
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
                      (v38/*: any*/)
                    ],
                    "type": "ProjectV2",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v11/*: any*/),
                      (v39/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v4/*: any*/),
                      (v40/*: any*/),
                      (v39/*: any*/)
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
            "selections": (v41/*: any*/),
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
            "selections": (v41/*: any*/),
            "type": "UnlockedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v41/*: any*/),
            "type": "PinnedEvent",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": (v41/*: any*/),
            "type": "UnpinnedEvent",
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
            "selections": (v42/*: any*/),
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
              (v23/*: any*/),
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
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": (v18/*: any*/),
                        "storageKey": null
                      }
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
                  (v31/*: any*/),
                  (v36/*: any*/),
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
                  (v40/*: any*/),
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
                            "selections": (v45/*: any*/),
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "CertificateAttributes",
                            "kind": "LinkedField",
                            "name": "subject",
                            "plural": false,
                            "selections": (v45/*: any*/),
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
                      (v29/*: any*/),
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
            "selections": (v46/*: any*/),
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
            "selections": [
              (v3/*: any*/),
              (v23/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Project",
                "kind": "LinkedField",
                "name": "project",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v8/*: any*/),
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
            "selections": (v46/*: any*/),
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
                      (v47/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v11/*: any*/),
                      (v2/*: any*/),
                      (v47/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v48/*: any*/),
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
                    "selections": (v49/*: any*/),
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": (v49/*: any*/),
                    "type": "PullRequest",
                    "abstractKey": null
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v48/*: any*/),
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
              (v50/*: any*/)
            ],
            "type": "AddedToProjectV2Event",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v23/*: any*/),
              (v50/*: any*/)
            ],
            "type": "RemovedFromProjectV2Event",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v5/*: any*/),
              (v23/*: any*/),
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
              (v5/*: any*/),
              (v23/*: any*/),
              (v3/*: any*/)
            ],
            "type": "ConvertedFromDraftEvent",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"SSC_asdkasd\")"
      }
    ]
  },
  "params": {
    "id": "2eccf126a9af0c2217f6b38b81deae1d",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isComment": (v51/*: any*/),
        "node.__isReactable": (v51/*: any*/),
        "node.__typename": (v51/*: any*/),
        "node.actor": (v52/*: any*/),
        "node.actor.__isActor": (v51/*: any*/),
        "node.actor.__typename": (v51/*: any*/),
        "node.actor.avatarUrl": (v53/*: any*/),
        "node.actor.id": (v54/*: any*/),
        "node.actor.login": (v51/*: any*/),
        "node.assignee": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Assignee"
        },
        "node.assignee.__isNode": (v51/*: any*/),
        "node.assignee.__typename": (v51/*: any*/),
        "node.assignee.id": (v54/*: any*/),
        "node.assignee.login": (v51/*: any*/),
        "node.author": (v52/*: any*/),
        "node.author.__typename": (v51/*: any*/),
        "node.author.avatarUrl": (v53/*: any*/),
        "node.author.id": (v54/*: any*/),
        "node.author.login": (v51/*: any*/),
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
        "node.authorToRepoOwnerSponsorship.createdAt": (v55/*: any*/),
        "node.authorToRepoOwnerSponsorship.id": (v54/*: any*/),
        "node.authorToRepoOwnerSponsorship.isActive": (v56/*: any*/),
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
        "node.blockedUser": (v57/*: any*/),
        "node.blockedUser.id": (v54/*: any*/),
        "node.blockedUser.login": (v51/*: any*/),
        "node.body": (v51/*: any*/),
        "node.bodyHTML": (v58/*: any*/),
        "node.bodyVersion": (v51/*: any*/),
        "node.canonical": (v59/*: any*/),
        "node.canonical.__isNode": (v51/*: any*/),
        "node.canonical.__isReferencedSubject": (v51/*: any*/),
        "node.canonical.__typename": (v51/*: any*/),
        "node.canonical.id": (v54/*: any*/),
        "node.canonical.isDraft": (v56/*: any*/),
        "node.canonical.isInMergeQueue": (v56/*: any*/),
        "node.canonical.issueTitleHTML": (v51/*: any*/),
        "node.canonical.number": (v60/*: any*/),
        "node.canonical.pullTitleHTML": (v58/*: any*/),
        "node.canonical.repository": (v61/*: any*/),
        "node.canonical.repository.id": (v54/*: any*/),
        "node.canonical.repository.isPrivate": (v56/*: any*/),
        "node.canonical.repository.name": (v51/*: any*/),
        "node.canonical.repository.owner": (v62/*: any*/),
        "node.canonical.repository.owner.__typename": (v51/*: any*/),
        "node.canonical.repository.owner.id": (v54/*: any*/),
        "node.canonical.repository.owner.login": (v51/*: any*/),
        "node.canonical.state": (v63/*: any*/),
        "node.canonical.stateReason": (v64/*: any*/),
        "node.canonical.url": (v53/*: any*/),
        "node.closer": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Closer"
        },
        "node.closer.__isNode": (v51/*: any*/),
        "node.closer.__typename": (v51/*: any*/),
        "node.closer.abbreviatedOid": (v51/*: any*/),
        "node.closer.id": (v54/*: any*/),
        "node.closer.number": (v60/*: any*/),
        "node.closer.repository": (v61/*: any*/),
        "node.closer.repository.id": (v54/*: any*/),
        "node.closer.repository.name": (v51/*: any*/),
        "node.closer.repository.owner": (v62/*: any*/),
        "node.closer.repository.owner.__typename": (v51/*: any*/),
        "node.closer.repository.owner.id": (v54/*: any*/),
        "node.closer.repository.owner.login": (v51/*: any*/),
        "node.closer.title": (v51/*: any*/),
        "node.closer.url": (v53/*: any*/),
        "node.closingProjectItemStatus": (v65/*: any*/),
        "node.commit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Commit"
        },
        "node.commit.abbreviatedOid": (v51/*: any*/),
        "node.commit.hasSignature": (v56/*: any*/),
        "node.commit.id": (v54/*: any*/),
        "node.commit.message": (v51/*: any*/),
        "node.commit.messageBodyHTML": (v58/*: any*/),
        "node.commit.messageHeadlineHTML": (v58/*: any*/),
        "node.commit.repository": (v61/*: any*/),
        "node.commit.repository.defaultBranch": (v51/*: any*/),
        "node.commit.repository.id": (v54/*: any*/),
        "node.commit.repository.name": (v51/*: any*/),
        "node.commit.repository.owner": (v62/*: any*/),
        "node.commit.repository.owner.__typename": (v51/*: any*/),
        "node.commit.repository.owner.id": (v54/*: any*/),
        "node.commit.repository.owner.login": (v51/*: any*/),
        "node.commit.signature": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "GitSignature"
        },
        "node.commit.signature.__typename": (v51/*: any*/),
        "node.commit.signature.issuer": (v66/*: any*/),
        "node.commit.signature.issuer.commonName": (v65/*: any*/),
        "node.commit.signature.issuer.emailAddress": (v65/*: any*/),
        "node.commit.signature.issuer.organization": (v65/*: any*/),
        "node.commit.signature.issuer.organizationUnit": (v65/*: any*/),
        "node.commit.signature.keyFingerprint": (v65/*: any*/),
        "node.commit.signature.keyId": (v65/*: any*/),
        "node.commit.signature.signer": (v57/*: any*/),
        "node.commit.signature.signer.avatarUrl": (v53/*: any*/),
        "node.commit.signature.signer.id": (v54/*: any*/),
        "node.commit.signature.signer.login": (v51/*: any*/),
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
        "node.commit.signature.subject": (v66/*: any*/),
        "node.commit.signature.subject.commonName": (v65/*: any*/),
        "node.commit.signature.subject.emailAddress": (v65/*: any*/),
        "node.commit.signature.subject.organization": (v65/*: any*/),
        "node.commit.signature.subject.organizationUnit": (v65/*: any*/),
        "node.commit.signature.wasSignedByGitHub": (v56/*: any*/),
        "node.commit.url": (v53/*: any*/),
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
        "node.createdAt": (v55/*: any*/),
        "node.createdViaEmail": (v56/*: any*/),
        "node.currentTitle": (v51/*: any*/),
        "node.databaseId": (v67/*: any*/),
        "node.deletedCommentAuthor": (v52/*: any*/),
        "node.deletedCommentAuthor.__typename": (v51/*: any*/),
        "node.deletedCommentAuthor.id": (v54/*: any*/),
        "node.deletedCommentAuthor.login": (v51/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v54/*: any*/),
        "node.discussion.number": (v60/*: any*/),
        "node.discussion.url": (v53/*: any*/),
        "node.duplicateOf": (v59/*: any*/),
        "node.duplicateOf.__isNode": (v51/*: any*/),
        "node.duplicateOf.__isReferencedSubject": (v51/*: any*/),
        "node.duplicateOf.__typename": (v51/*: any*/),
        "node.duplicateOf.id": (v54/*: any*/),
        "node.duplicateOf.isDraft": (v56/*: any*/),
        "node.duplicateOf.isInMergeQueue": (v56/*: any*/),
        "node.duplicateOf.issueTitleHTML": (v51/*: any*/),
        "node.duplicateOf.number": (v60/*: any*/),
        "node.duplicateOf.pullTitleHTML": (v58/*: any*/),
        "node.duplicateOf.repository": (v61/*: any*/),
        "node.duplicateOf.repository.id": (v54/*: any*/),
        "node.duplicateOf.repository.isPrivate": (v56/*: any*/),
        "node.duplicateOf.repository.name": (v51/*: any*/),
        "node.duplicateOf.repository.owner": (v62/*: any*/),
        "node.duplicateOf.repository.owner.__typename": (v51/*: any*/),
        "node.duplicateOf.repository.owner.id": (v54/*: any*/),
        "node.duplicateOf.repository.owner.login": (v51/*: any*/),
        "node.duplicateOf.state": (v63/*: any*/),
        "node.duplicateOf.stateReason": (v64/*: any*/),
        "node.duplicateOf.url": (v53/*: any*/),
        "node.fromRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.fromRepository.id": (v54/*: any*/),
        "node.fromRepository.nameWithOwner": (v51/*: any*/),
        "node.fromRepository.url": (v53/*: any*/),
        "node.id": (v54/*: any*/),
        "node.innerSource": (v68/*: any*/),
        "node.innerSource.__isNode": (v51/*: any*/),
        "node.innerSource.__isReferencedSubject": (v51/*: any*/),
        "node.innerSource.__typename": (v51/*: any*/),
        "node.innerSource.id": (v54/*: any*/),
        "node.innerSource.isDraft": (v56/*: any*/),
        "node.innerSource.isInMergeQueue": (v56/*: any*/),
        "node.innerSource.issueTitleHTML": (v51/*: any*/),
        "node.innerSource.number": (v60/*: any*/),
        "node.innerSource.pullTitleHTML": (v58/*: any*/),
        "node.innerSource.repository": (v61/*: any*/),
        "node.innerSource.repository.id": (v54/*: any*/),
        "node.innerSource.repository.isPrivate": (v56/*: any*/),
        "node.innerSource.repository.name": (v51/*: any*/),
        "node.innerSource.repository.owner": (v62/*: any*/),
        "node.innerSource.repository.owner.__typename": (v51/*: any*/),
        "node.innerSource.repository.owner.id": (v54/*: any*/),
        "node.innerSource.repository.owner.login": (v51/*: any*/),
        "node.innerSource.state": (v63/*: any*/),
        "node.innerSource.stateReason": (v64/*: any*/),
        "node.innerSource.url": (v53/*: any*/),
        "node.isCanonicalOfClosedDuplicate": (v69/*: any*/),
        "node.isHidden": (v56/*: any*/),
        "node.issue": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Issue"
        },
        "node.issue.author": (v52/*: any*/),
        "node.issue.author.__typename": (v51/*: any*/),
        "node.issue.author.id": (v54/*: any*/),
        "node.issue.author.login": (v51/*: any*/),
        "node.issue.databaseId": (v67/*: any*/),
        "node.issue.id": (v54/*: any*/),
        "node.issue.locked": (v56/*: any*/),
        "node.issue.number": (v60/*: any*/),
        "node.label": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Label"
        },
        "node.label.color": (v51/*: any*/),
        "node.label.description": (v65/*: any*/),
        "node.label.id": (v54/*: any*/),
        "node.label.name": (v51/*: any*/),
        "node.label.nameHTML": (v51/*: any*/),
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
        "node.lastUserContentEdit.editor": (v52/*: any*/),
        "node.lastUserContentEdit.editor.__typename": (v51/*: any*/),
        "node.lastUserContentEdit.editor.id": (v54/*: any*/),
        "node.lastUserContentEdit.editor.login": (v51/*: any*/),
        "node.lastUserContentEdit.editor.url": (v53/*: any*/),
        "node.lastUserContentEdit.id": (v54/*: any*/),
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
        "node.milestone.id": (v54/*: any*/),
        "node.milestone.url": (v53/*: any*/),
        "node.milestoneTitle": (v51/*: any*/),
        "node.minimizedReason": (v65/*: any*/),
        "node.pendingBlock": (v69/*: any*/),
        "node.pendingMinimizeReason": (v65/*: any*/),
        "node.pendingUnblock": (v69/*: any*/),
        "node.pendingUndo": (v69/*: any*/),
        "node.previousProjectColumnName": (v51/*: any*/),
        "node.previousStatus": (v51/*: any*/),
        "node.previousTitle": (v51/*: any*/),
        "node.project": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Project"
        },
        "node.project.id": (v54/*: any*/),
        "node.project.name": (v51/*: any*/),
        "node.project.title": (v51/*: any*/),
        "node.project.url": (v53/*: any*/),
        "node.projectColumnName": (v51/*: any*/),
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
        "node.reactionGroups.reactors.nodes.__isNode": (v51/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v51/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v54/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v51/*: any*/),
        "node.reactionGroups.reactors.totalCount": (v60/*: any*/),
        "node.reactionGroups.viewerHasReacted": (v56/*: any*/),
        "node.referencedAt": (v55/*: any*/),
        "node.repository": (v61/*: any*/),
        "node.repository.databaseId": (v67/*: any*/),
        "node.repository.id": (v54/*: any*/),
        "node.repository.isPrivate": (v56/*: any*/),
        "node.repository.name": (v51/*: any*/),
        "node.repository.nameWithOwner": (v51/*: any*/),
        "node.repository.owner": (v62/*: any*/),
        "node.repository.owner.__typename": (v51/*: any*/),
        "node.repository.owner.id": (v54/*: any*/),
        "node.repository.owner.login": (v51/*: any*/),
        "node.repository.owner.url": (v53/*: any*/),
        "node.repository.slashCommandsEnabled": (v56/*: any*/),
        "node.showSpammyBadge": (v56/*: any*/),
        "node.stateReason": (v64/*: any*/),
        "node.status": (v51/*: any*/),
        "node.subject": (v68/*: any*/),
        "node.subject.__isNode": (v51/*: any*/),
        "node.subject.__typename": (v51/*: any*/),
        "node.subject.id": (v54/*: any*/),
        "node.subject.isDraft": (v56/*: any*/),
        "node.subject.isInMergeQueue": (v56/*: any*/),
        "node.subject.number": (v60/*: any*/),
        "node.subject.repository": (v61/*: any*/),
        "node.subject.repository.id": (v54/*: any*/),
        "node.subject.repository.name": (v51/*: any*/),
        "node.subject.repository.owner": (v62/*: any*/),
        "node.subject.repository.owner.__typename": (v51/*: any*/),
        "node.subject.repository.owner.id": (v54/*: any*/),
        "node.subject.repository.owner.login": (v51/*: any*/),
        "node.subject.state": (v63/*: any*/),
        "node.subject.title": (v51/*: any*/),
        "node.subject.url": (v53/*: any*/),
        "node.target": (v68/*: any*/),
        "node.target.__isNode": (v51/*: any*/),
        "node.target.__typename": (v51/*: any*/),
        "node.target.id": (v54/*: any*/),
        "node.target.repository": (v61/*: any*/),
        "node.target.repository.id": (v54/*: any*/),
        "node.url": (v53/*: any*/),
        "node.viewerCanBlockFromOrg": (v56/*: any*/),
        "node.viewerCanDelete": (v56/*: any*/),
        "node.viewerCanMinimize": (v56/*: any*/),
        "node.viewerCanReadUserContentEdits": (v56/*: any*/),
        "node.viewerCanReport": (v56/*: any*/),
        "node.viewerCanReportToMaintainer": (v56/*: any*/),
        "node.viewerCanUnblockFromOrg": (v56/*: any*/),
        "node.viewerCanUndo": (v56/*: any*/),
        "node.viewerCanUpdate": (v56/*: any*/),
        "node.viewerDidAuthor": (v56/*: any*/),
        "node.willCloseSubject": (v56/*: any*/),
        "node.willCloseTarget": (v56/*: any*/)
      }
    },
    "name": "IssueEventWrapperQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b09cb6bf41b549add39a317072432431";

export default node;
