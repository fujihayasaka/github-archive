/**
 * @generated SignedSource<<6e4673f7b354c110bcfd181fc2465850>>
 * @relayHash 91d5eb4b023d9a0256c1a357fcfac031
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 91d5eb4b023d9a0256c1a357fcfac031

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerSubscription$variables = {
  connections: ReadonlyArray<string>;
  issueId: string;
  skip?: number | null | undefined;
};
export type IssueViewerSubscription$data = {
  readonly issueUpdated: {
    readonly commentReactionUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
    } | null | undefined;
    readonly commentUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueCommentEditorBodyFragment" | "IssueCommentViewerMarkdownViewer">;
    } | null | undefined;
    readonly deletedCommentId: string | null | undefined;
    readonly issueBodyUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueBodyContent">;
    } | null | undefined;
    readonly issueDependenciesSummaryUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"HeaderBlockedBySummary" | "RelationshipsSectionFragment">;
    } | null | undefined;
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionAssignees" | "DevelopmentSectionFragment" | "LabelsSectionAssignedLabels" | "MilestonesSectionMilestone" | "ProjectsSectionFragment">;
    } | null | undefined;
    readonly issueReactionUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
    } | null | undefined;
    readonly issueStateUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"HeaderState" | "IssueActions">;
    } | null | undefined;
    readonly issueTimelineUpdated: {
      readonly timelineItems: {
        readonly edges: ReadonlyArray<{
          readonly node: {
            readonly __typename: string;
            readonly __id: string;
            readonly " $fragmentSpreads": FragmentRefs<"AddedToProjectV2Event" | "AssignedEvent" | "ClosedEvent" | "CommentDeletedEvent" | "ConnectedEvent" | "ConvertedFromDraftEvent" | "ConvertedToDiscussionEvent" | "CrossReferencedEvent" | "DemilestonedEvent" | "DisconnectedEvent" | "IssueComment_issueComment" | "IssueTypeAddedEvent" | "IssueTypeChangedEvent" | "IssueTypeRemovedEvent" | "LabeledEvent" | "LockedEvent" | "MarkedAsDuplicateEvent" | "MentionedEvent" | "MilestonedEvent" | "ParentIssueAddedEvent" | "ParentIssueRemovedEvent" | "PinnedEvent" | "ProjectV2ItemStatusChangedEvent" | "ReactionViewerRelayGroups" | "ReferencedEvent" | "RemovedFromProjectV2Event" | "RenamedTitleEvent" | "ReopenedEvent" | "SubIssueAddedEvent" | "SubIssueRemovedEvent" | "SubscribedEvent" | "TransferredEvent" | "UnassignedEvent" | "UnlabeledEvent" | "UnlockedEvent" | "UnmarkedAsDuplicateEvent" | "UnpinnedEvent" | "UnsubscribedEvent" | "UserBlockedEvent">;
          } | null | undefined;
        } | null | undefined> | null | undefined;
        readonly totalCount: number;
      };
    } | null | undefined;
    readonly issueTitleUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"Header">;
    } | null | undefined;
    readonly issueTransferStateUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueBodyViewerSubIssues" | "SubIssuesList" | "useHasSubIssues">;
    } | null | undefined;
    readonly issueTypeUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"HeaderIssueType" | "TypesSectionTypeFragment">;
    } | null | undefined;
    readonly parentIssueUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"HeaderParentTitle" | "RelationshipsSectionFragment">;
    } | null | undefined;
    readonly subIssuesUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesList" | "useHasSubIssues">;
    } | null | undefined;
  };
};
export type IssueViewerSubscription = {
  response: IssueViewerSubscription$data;
  variables: IssueViewerSubscription$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "connections"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "issueId"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "skip"
},
v3 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "issueId"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "deletedCommentId",
  "storageKey": null
},
v5 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "ReactionViewerRelayGroups"
},
v6 = [
  (v5/*: any*/)
],
v7 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "SubIssuesList"
},
v8 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "useHasSubIssues"
},
v9 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "RelationshipsSectionFragment"
},
v10 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v11 = [
  (v10/*: any*/),
  {
    "kind": "Variable",
    "name": "skip",
    "variableName": "skip"
  },
  {
    "kind": "Literal",
    "name": "visibleEventsOnly",
    "value": true
  }
],
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
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
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
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
  "name": "name",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
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
  "name": "isCopilot",
  "storageKey": null
},
v21 = {
  "kind": "InlineFragment",
  "selections": [
    (v20/*: any*/)
  ],
  "type": "Bot",
  "abstractKey": null
},
v22 = [
  (v15/*: any*/)
],
v23 = {
  "kind": "InlineFragment",
  "selections": (v22/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v24 = {
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
            (v15/*: any*/),
            (v16/*: any*/),
            (v17/*: any*/),
            (v18/*: any*/),
            (v19/*: any*/),
            (v21/*: any*/)
          ],
          "type": "Actor",
          "abstractKey": "__isActor"
        },
        (v23/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "assignedActors(first:20)"
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "concreteType": "Milestone",
  "kind": "LinkedField",
  "name": "milestone",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    (v25/*: any*/),
    (v26/*: any*/),
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
    (v27/*: any*/),
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
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v30 = [
  (v13/*: any*/),
  (v16/*: any*/),
  (v15/*: any*/)
],
v31 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v30/*: any*/),
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "target",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "oid",
      "storageKey": null
    },
    (v15/*: any*/),
    (v13/*: any*/)
  ],
  "storageKey": null
},
v35 = [
  (v12/*: any*/)
],
v36 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestConnection",
  "kind": "LinkedField",
  "name": "associatedPullRequests",
  "plural": false,
  "selections": (v35/*: any*/),
  "storageKey": null
},
v37 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v22/*: any*/),
  "storageKey": null
},
v38 = {
  "kind": "Literal",
  "name": "includeClosedPrs",
  "value": true
},
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v40 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v41 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
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
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v32/*: any*/),
    (v15/*: any*/),
    (v17/*: any*/),
    (v31/*: any*/)
  ],
  "storageKey": null
},
v44 = {
  "alias": "linkedPullRequests",
  "args": [
    (v10/*: any*/),
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
        (v43/*: any*/),
        (v39/*: any*/),
        (v40/*: any*/),
        (v27/*: any*/),
        (v33/*: any*/),
        (v15/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "closedByPullRequestsReferences(first:10,includeClosedPrs:false,orderByState:true)"
},
v45 = {
  "kind": "Literal",
  "name": "first",
  "value": 100
},
v46 = [
  (v45/*: any*/),
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v51 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasNextPage",
  "storageKey": null
},
v52 = {
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
    (v51/*: any*/)
  ],
  "storageKey": null
},
v53 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": (v46/*: any*/),
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
                (v15/*: any*/),
                (v47/*: any*/),
                (v17/*: any*/),
                (v48/*: any*/),
                (v49/*: any*/),
                (v27/*: any*/),
                (v13/*: any*/)
              ],
              "storageKey": null
            },
            (v50/*: any*/)
          ],
          "storageKey": null
        },
        (v52/*: any*/)
      ],
      "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
    },
    {
      "alias": null,
      "args": (v46/*: any*/),
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
v54 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v55 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v54/*: any*/)
  ],
  "storageKey": null
},
v56 = [
  (v10/*: any*/)
],
v57 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v58 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v60 = {
  "alias": null,
  "args": (v56/*: any*/),
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
            (v15/*: any*/),
            (v54/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v15/*: any*/),
                (v25/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v57/*: any*/),
                (v27/*: any*/),
                {
                  "alias": null,
                  "args": (v58/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v13/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v15/*: any*/),
                        (v17/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v15/*: any*/),
                            (v59/*: any*/),
                            (v17/*: any*/),
                            (v48/*: any*/),
                            (v47/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v49/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v23/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v26/*: any*/),
                (v33/*: any*/),
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
              "args": (v58/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v13/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v15/*: any*/),
                    (v59/*: any*/),
                    (v17/*: any*/),
                    (v48/*: any*/),
                    (v47/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v23/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v13/*: any*/)
          ],
          "storageKey": null
        },
        (v50/*: any*/)
      ],
      "storageKey": null
    },
    (v52/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v61 = {
  "alias": null,
  "args": (v56/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v62 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdateMetadata",
  "storageKey": null
},
v63 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v64 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v65 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v66 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v67 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v68 = [
  (v17/*: any*/),
  (v47/*: any*/),
  (v15/*: any*/)
],
v69 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v68/*: any*/),
  "storageKey": null
},
v70 = {
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
v71 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v31/*: any*/),
    (v15/*: any*/)
  ],
  "storageKey": null
},
v72 = {
  "alias": null,
  "args": null,
  "concreteType": "Issue",
  "kind": "LinkedField",
  "name": "duplicateOf",
  "plural": false,
  "selections": [
    (v33/*: any*/),
    (v27/*: any*/),
    (v71/*: any*/),
    (v15/*: any*/)
  ],
  "storageKey": null
},
v73 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "total",
  "storageKey": null
},
v74 = {
  "alias": null,
  "args": null,
  "concreteType": "SubIssuesSummary",
  "kind": "LinkedField",
  "name": "subIssuesSummary",
  "plural": false,
  "selections": [
    (v73/*: any*/),
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
v75 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v32/*: any*/),
    (v15/*: any*/)
  ],
  "storageKey": null
},
v76 = [
  (v16/*: any*/)
],
v77 = {
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
            (v12/*: any*/),
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
                  "selections": (v76/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v16/*: any*/),
                    (v20/*: any*/)
                  ],
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v76/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v76/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                },
                (v23/*: any*/)
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
v78 = [
  (v77/*: any*/),
  (v15/*: any*/)
],
v79 = {
  "alias": null,
  "args": [
    (v64/*: any*/)
  ],
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": "bodyHTML(unfurlReferences:true)"
},
v80 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v81 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": (v30/*: any*/),
  "storageKey": null
},
v82 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authorAssociation",
  "storageKey": null
},
v83 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v84 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanMinimize",
  "storageKey": null
},
v85 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReport",
  "storageKey": null
},
v86 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReportToMaintainer",
  "storageKey": null
},
v87 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanBlockFromOrg",
  "storageKey": null
},
v88 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUnblockFromOrg",
  "storageKey": null
},
v89 = {
  "alias": "isHidden",
  "args": null,
  "kind": "ScalarField",
  "name": "isMinimized",
  "storageKey": null
},
v90 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "minimizedReason",
  "storageKey": null
},
v91 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "showSpammyBadge",
  "storageKey": null
},
v92 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdViaEmail",
  "storageKey": null
},
v93 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v94 = {
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
    (v15/*: any*/)
  ],
  "storageKey": null
},
v95 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    (v15/*: any*/),
    (v16/*: any*/),
    (v27/*: any*/)
  ],
  "storageKey": null
},
v96 = {
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
            (v27/*: any*/),
            (v16/*: any*/),
            (v15/*: any*/)
          ],
          "storageKey": null
        },
        (v15/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
},
v97 = {
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
v98 = {
  "alias": null,
  "args": [
    (v45/*: any*/)
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
        (v15/*: any*/),
        (v39/*: any*/),
        (v70/*: any*/),
        {
          "alias": null,
          "args": (v56/*: any*/),
          "concreteType": "UserConnection",
          "kind": "LinkedField",
          "name": "assignees",
          "plural": false,
          "selections": [
            (v12/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "UserEdge",
              "kind": "LinkedField",
              "name": "edges",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "User",
                  "kind": "LinkedField",
                  "name": "node",
                  "plural": false,
                  "selections": [
                    (v15/*: any*/),
                    (v16/*: any*/),
                    (v80/*: any*/)
                  ],
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": "assignees(first:10)"
        },
        (v27/*: any*/),
        (v71/*: any*/),
        (v29/*: any*/),
        (v33/*: any*/),
        (v25/*: any*/),
        (v67/*: any*/),
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueType",
          "kind": "LinkedField",
          "name": "issueType",
          "plural": false,
          "selections": [
            (v15/*: any*/),
            (v17/*: any*/),
            (v47/*: any*/)
          ],
          "storageKey": null
        },
        (v74/*: any*/),
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 0
            },
            (v38/*: any*/)
          ],
          "concreteType": "PullRequestConnection",
          "kind": "LinkedField",
          "name": "closedByPullRequestsReferences",
          "plural": false,
          "selections": (v35/*: any*/),
          "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
        },
        (v26/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "subIssues(first:100)"
},
v99 = {
  "alias": "subIssuesConnection",
  "args": null,
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "subIssues",
  "plural": false,
  "selections": (v35/*: any*/),
  "storageKey": null
},
v100 = {
  "alias": null,
  "args": null,
  "concreteType": "Issue",
  "kind": "LinkedField",
  "name": "parent",
  "plural": false,
  "selections": (v22/*: any*/),
  "storageKey": null
},
v101 = {
  "alias": null,
  "args": null,
  "concreteType": "SubIssuesSummary",
  "kind": "LinkedField",
  "name": "subIssuesSummary",
  "plural": false,
  "selections": [
    (v73/*: any*/)
  ],
  "storageKey": null
},
v102 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v32/*: any*/),
    (v31/*: any*/),
    (v15/*: any*/),
    (v54/*: any*/)
  ],
  "storageKey": null
},
v103 = {
  "kind": "Literal",
  "name": "ranked",
  "value": true
},
v104 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 3
  },
  (v103/*: any*/)
],
v105 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v15/*: any*/),
      (v25/*: any*/),
      (v67/*: any*/),
      (v27/*: any*/),
      (v33/*: any*/),
      (v75/*: any*/),
      (v39/*: any*/),
      (v70/*: any*/)
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
      (v51/*: any*/)
    ],
    "storageKey": null
  }
],
v106 = {
  "alias": "topBlockedBy",
  "args": (v104/*: any*/),
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "blockedBy",
  "plural": false,
  "selections": (v105/*: any*/),
  "storageKey": "blockedBy(first:3,ranked:true)"
},
v107 = {
  "alias": "topBlocking",
  "args": (v104/*: any*/),
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "blocking",
  "plural": false,
  "selections": (v105/*: any*/),
  "storageKey": "blocking(first:3,ranked:true)"
},
v108 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueDependenciesSummary",
  "kind": "LinkedField",
  "name": "issueDependenciesSummary",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "blockedBy",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "blocking",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v109 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v110 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v13/*: any*/),
    (v109/*: any*/),
    (v19/*: any*/),
    (v16/*: any*/),
    (v18/*: any*/),
    (v21/*: any*/),
    (v15/*: any*/)
  ],
  "storageKey": null
},
v111 = [
  (v42/*: any*/),
  (v29/*: any*/),
  (v110/*: any*/)
],
v112 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v113 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    (v17/*: any*/),
    (v66/*: any*/),
    (v31/*: any*/)
  ],
  "storageKey": null
},
v114 = {
  "kind": "InlineFragment",
  "selections": [
    (v15/*: any*/),
    (v112/*: any*/),
    (v27/*: any*/),
    (v33/*: any*/),
    (v70/*: any*/),
    (v113/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v115 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v116 = {
  "kind": "InlineFragment",
  "selections": [
    (v15/*: any*/),
    (v115/*: any*/),
    (v27/*: any*/),
    (v33/*: any*/),
    (v39/*: any*/),
    (v40/*: any*/),
    (v41/*: any*/),
    (v113/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v117 = {
  "kind": "InlineFragment",
  "selections": [
    (v114/*: any*/),
    (v116/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v118 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v119 = [
  (v29/*: any*/),
  (v42/*: any*/),
  (v110/*: any*/)
],
v120 = [
  (v29/*: any*/),
  (v42/*: any*/),
  (v110/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v48/*: any*/),
      (v17/*: any*/),
      (v47/*: any*/),
      (v15/*: any*/),
      (v49/*: any*/)
    ],
    "storageKey": null
  }
],
v121 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "resourcePath",
  "storageKey": null
},
v122 = [
  (v121/*: any*/)
],
v123 = {
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
      "selections": [
        (v16/*: any*/),
        {
          "kind": "InlineFragment",
          "selections": (v122/*: any*/),
          "type": "User",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v122/*: any*/),
          "type": "Mannequin",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": (v122/*: any*/),
          "type": "Organization",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v121/*: any*/),
            (v20/*: any*/)
          ],
          "type": "Bot",
          "abstractKey": null
        }
      ],
      "type": "Actor",
      "abstractKey": "__isActor"
    },
    (v23/*: any*/)
  ],
  "storageKey": null
},
v124 = [
  (v29/*: any*/),
  (v42/*: any*/),
  (v110/*: any*/),
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
      (v27/*: any*/),
      (v15/*: any*/)
    ],
    "storageKey": null
  }
],
v125 = [
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
v126 = [
  (v29/*: any*/),
  (v110/*: any*/),
  (v42/*: any*/),
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
          (v25/*: any*/),
          (v27/*: any*/),
          (v33/*: any*/),
          (v39/*: any*/),
          (v40/*: any*/),
          (v41/*: any*/),
          (v71/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v23/*: any*/)
    ],
    "storageKey": null
  }
],
v127 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v112/*: any*/),
        (v27/*: any*/),
        (v70/*: any*/),
        (v113/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v115/*: any*/),
        (v27/*: any*/),
        (v39/*: any*/),
        (v40/*: any*/),
        (v41/*: any*/),
        (v113/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v128 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v129 = [
  (v117/*: any*/)
],
v130 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v25/*: any*/),
    (v27/*: any*/),
    (v15/*: any*/)
  ],
  "storageKey": null
},
v131 = [
  (v29/*: any*/),
  (v110/*: any*/),
  (v42/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": [
      (v29/*: any*/),
      (v15/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v13/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v112/*: any*/),
              (v27/*: any*/),
              (v33/*: any*/),
              (v70/*: any*/),
              (v113/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v115/*: any*/),
              (v27/*: any*/),
              (v33/*: any*/),
              (v39/*: any*/),
              (v40/*: any*/),
              (v41/*: any*/),
              (v113/*: any*/)
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
v132 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v17/*: any*/),
    (v66/*: any*/),
    (v31/*: any*/)
  ],
  "storageKey": null
},
v133 = [
  (v29/*: any*/),
  (v110/*: any*/),
  (v42/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": [
      (v37/*: any*/),
      (v29/*: any*/),
      (v15/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v13/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v112/*: any*/),
              (v27/*: any*/),
              (v33/*: any*/),
              (v70/*: any*/),
              (v132/*: any*/)
            ],
            "type": "Issue",
            "abstractKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v115/*: any*/),
              (v27/*: any*/),
              (v33/*: any*/),
              (v39/*: any*/),
              (v40/*: any*/),
              (v41/*: any*/),
              (v132/*: any*/)
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
v134 = [
  (v29/*: any*/),
  (v110/*: any*/),
  (v42/*: any*/),
  (v69/*: any*/)
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
    "name": "IssueViewerSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "LabelsSectionAssignedLabels"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "AssigneesSectionAssignees"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "MilestonesSectionMilestone"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "ProjectsSectionFragment"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "DevelopmentSectionFragment"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueBodyUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyContent"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTitleUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "Header"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueStateUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "HeaderState"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueActions"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTypeUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "HeaderIssueType"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "TypesSectionTypeFragment"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueReactionUpdated",
            "plural": false,
            "selections": (v6/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueComment",
            "kind": "LinkedField",
            "name": "commentReactionUpdated",
            "plural": false,
            "selections": (v6/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueComment",
            "kind": "LinkedField",
            "name": "commentUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueCommentViewerMarkdownViewer"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueCommentEditorBodyFragment"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssuesUpdated",
            "plural": false,
            "selections": [
              (v7/*: any*/),
              (v8/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTransferStateUpdated",
            "plural": false,
            "selections": [
              (v7/*: any*/),
              (v8/*: any*/),
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyViewerSubIssues"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "parentIssueUpdated",
            "plural": false,
            "selections": [
              (v9/*: any*/),
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "HeaderParentTitle"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueDependenciesSummaryUpdated",
            "plural": false,
            "selections": [
              (v9/*: any*/),
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "HeaderBlockedBySummary"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTimelineUpdated",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": (v11/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v12/*: any*/),
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
                          (v13/*: any*/),
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
                            "name": "IssueComment_issueComment"
                          },
                          (v5/*: any*/),
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
                          },
                          (v14/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "EventSubscription",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [
      (v1/*: any*/),
      (v0/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueViewerSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          {
            "alias": null,
            "args": null,
            "filters": null,
            "handle": "deleteRecord",
            "key": "",
            "kind": "ScalarHandle",
            "name": "deletedCommentId"
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              (v24/*: any*/),
              (v28/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v15/*: any*/),
                  (v29/*: any*/),
                  (v17/*: any*/),
                  (v31/*: any*/),
                  (v32/*: any*/)
                ],
                "storageKey": null
              },
              (v15/*: any*/),
              (v25/*: any*/),
              (v33/*: any*/),
              (v29/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 25
                  }
                ],
                "concreteType": "LinkedBranchConnection",
                "kind": "LinkedField",
                "name": "linkedBranches",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "LinkedBranch",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v15/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Ref",
                        "kind": "LinkedField",
                        "name": "ref",
                        "plural": false,
                        "selections": [
                          (v17/*: any*/),
                          (v15/*: any*/),
                          (v13/*: any*/),
                          (v34/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": [
                              (v15/*: any*/),
                              (v32/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Ref",
                                "kind": "LinkedField",
                                "name": "defaultBranchRef",
                                "plural": false,
                                "selections": [
                                  (v17/*: any*/),
                                  (v15/*: any*/),
                                  (v34/*: any*/),
                                  (v36/*: any*/),
                                  (v37/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          (v36/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "linkedBranches(first:25)"
              },
              {
                "alias": null,
                "args": [
                  (v10/*: any*/),
                  (v38/*: any*/)
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
                      (v15/*: any*/),
                      (v13/*: any*/),
                      (v27/*: any*/),
                      (v33/*: any*/),
                      (v25/*: any*/),
                      (v39/*: any*/),
                      (v40/*: any*/),
                      (v41/*: any*/),
                      (v42/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v15/*: any*/),
                          (v17/*: any*/),
                          (v32/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "owner",
                            "plural": false,
                            "selections": [
                              (v16/*: any*/),
                              (v13/*: any*/),
                              (v15/*: any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "closedByPullRequestsReferences(first:10,includeClosedPrs:true)"
              },
              (v44/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanLinkBranches",
                "storageKey": null
              },
              (v53/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v55/*: any*/),
                      (v60/*: any*/),
                      (v61/*: any*/),
                      (v62/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v55/*: any*/),
                      (v60/*: any*/),
                      (v61/*: any*/),
                      (v57/*: any*/)
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
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueBodyUpdated",
            "plural": false,
            "selections": [
              (v63/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v64/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v65/*: any*/),
              (v15/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTitleUpdated",
            "plural": false,
            "selections": [
              (v25/*: any*/),
              (v33/*: any*/),
              (v15/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v32/*: any*/),
                  (v15/*: any*/),
                  (v17/*: any*/),
                  (v31/*: any*/),
                  (v54/*: any*/),
                  (v66/*: any*/)
                ],
                "storageKey": null
              },
              (v67/*: any*/),
              (v27/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateNext",
                "storageKey": null
              },
              (v69/*: any*/),
              (v39/*: any*/),
              (v70/*: any*/),
              (v72/*: any*/),
              (v44/*: any*/),
              (v74/*: any*/),
              (v24/*: any*/),
              (v28/*: any*/),
              (v53/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueStateUpdated",
            "plural": false,
            "selections": [
              (v39/*: any*/),
              (v70/*: any*/),
              (v72/*: any*/),
              (v15/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v15/*: any*/),
                  (v32/*: any*/),
                  (v31/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTypeUpdated",
            "plural": false,
            "selections": [
              (v75/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "issueType",
                "plural": false,
                "selections": [
                  (v17/*: any*/),
                  (v47/*: any*/),
                  (v15/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isEnabled",
                    "storageKey": null
                  },
                  (v49/*: any*/)
                ],
                "storageKey": null
              },
              (v15/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueReactionUpdated",
            "plural": false,
            "selections": (v78/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueComment",
            "kind": "LinkedField",
            "name": "commentReactionUpdated",
            "plural": false,
            "selections": (v78/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueComment",
            "kind": "LinkedField",
            "name": "commentUpdated",
            "plural": false,
            "selections": [
              (v15/*: any*/),
              (v63/*: any*/),
              (v79/*: any*/),
              (v65/*: any*/),
              (v57/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v13/*: any*/),
                  (v16/*: any*/),
                  (v80/*: any*/),
                  (v15/*: any*/)
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
                  (v15/*: any*/),
                  (v29/*: any*/),
                  (v81/*: any*/),
                  (v33/*: any*/)
                ],
                "storageKey": null
              },
              (v29/*: any*/),
              (v27/*: any*/),
              (v42/*: any*/),
              (v82/*: any*/),
              (v83/*: any*/),
              (v84/*: any*/),
              (v85/*: any*/),
              (v86/*: any*/),
              (v87/*: any*/),
              (v88/*: any*/),
              (v89/*: any*/),
              (v90/*: any*/),
              (v91/*: any*/),
              (v92/*: any*/),
              (v93/*: any*/),
              (v94/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v15/*: any*/),
                  (v17/*: any*/),
                  (v95/*: any*/),
                  (v66/*: any*/)
                ],
                "storageKey": null
              },
              (v96/*: any*/),
              (v97/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssuesUpdated",
            "plural": false,
            "selections": [
              (v15/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v17/*: any*/),
                  (v15/*: any*/),
                  (v32/*: any*/),
                  (v31/*: any*/)
                ],
                "storageKey": null
              },
              (v98/*: any*/),
              (v99/*: any*/),
              (v100/*: any*/),
              (v101/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTransferStateUpdated",
            "plural": false,
            "selections": [
              (v15/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v17/*: any*/),
                  (v15/*: any*/),
                  (v32/*: any*/),
                  (v31/*: any*/),
                  (v54/*: any*/)
                ],
                "storageKey": null
              },
              (v98/*: any*/),
              (v99/*: any*/),
              (v100/*: any*/),
              (v101/*: any*/),
              (v62/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "parentIssueUpdated",
            "plural": false,
            "selections": [
              (v15/*: any*/),
              (v102/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": [
                  (v15/*: any*/),
                  (v25/*: any*/),
                  (v67/*: any*/),
                  (v27/*: any*/),
                  (v33/*: any*/),
                  (v43/*: any*/),
                  (v39/*: any*/),
                  (v70/*: any*/),
                  (v74/*: any*/)
                ],
                "storageKey": null
              },
              (v106/*: any*/),
              (v107/*: any*/),
              (v108/*: any*/),
              (v62/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueDependenciesSummaryUpdated",
            "plural": false,
            "selections": [
              (v15/*: any*/),
              (v102/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": [
                  (v15/*: any*/),
                  (v25/*: any*/),
                  (v67/*: any*/),
                  (v27/*: any*/),
                  (v33/*: any*/),
                  (v75/*: any*/),
                  (v39/*: any*/),
                  (v70/*: any*/),
                  (v74/*: any*/)
                ],
                "storageKey": null
              },
              (v106/*: any*/),
              (v107/*: any*/),
              (v108/*: any*/),
              (v62/*: any*/),
              (v39/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 1
                  },
                  (v103/*: any*/)
                ],
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
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
                      (v25/*: any*/),
                      (v33/*: any*/),
                      (v27/*: any*/),
                      (v71/*: any*/),
                      (v15/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "blockedBy(first:1,ranked:true)"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueTimelineUpdated",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": (v11/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v12/*: any*/),
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
                          (v13/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": (v111/*: any*/),
                            "type": "SubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v111/*: any*/),
                            "type": "UnsubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v111/*: any*/),
                            "type": "MentionedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v15/*: any*/),
                              (v29/*: any*/),
                              (v63/*: any*/),
                              (v79/*: any*/),
                              (v65/*: any*/),
                              (v57/*: any*/),
                              (v27/*: any*/),
                              (v42/*: any*/),
                              (v82/*: any*/),
                              (v83/*: any*/),
                              (v84/*: any*/),
                              (v85/*: any*/),
                              (v86/*: any*/),
                              (v87/*: any*/),
                              (v88/*: any*/),
                              (v89/*: any*/),
                              (v90/*: any*/),
                              (v91/*: any*/),
                              (v92/*: any*/),
                              (v93/*: any*/),
                              (v94/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "author",
                                "plural": false,
                                "selections": [
                                  (v13/*: any*/),
                                  (v15/*: any*/),
                                  (v16/*: any*/),
                                  (v80/*: any*/)
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
                                  (v15/*: any*/),
                                  (v17/*: any*/),
                                  (v95/*: any*/),
                                  (v66/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slashCommandsEnabled",
                                    "storageKey": null
                                  },
                                  (v32/*: any*/),
                                  (v29/*: any*/)
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
                                  (v33/*: any*/),
                                  (v15/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "locked",
                                    "storageKey": null
                                  },
                                  (v29/*: any*/),
                                  (v81/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v96/*: any*/),
                              (v97/*: any*/),
                              (v77/*: any*/)
                            ],
                            "type": "IssueComment",
                            "abstractKey": null
                          },
                          (v77/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              (v70/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "duplicateOf",
                                "plural": false,
                                "selections": [
                                  (v13/*: any*/),
                                  (v117/*: any*/),
                                  (v23/*: any*/)
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
                                      (v27/*: any*/),
                                      (v25/*: any*/)
                                    ],
                                    "type": "ProjectV2",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v27/*: any*/),
                                      (v33/*: any*/),
                                      (v71/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v27/*: any*/),
                                      (v118/*: any*/),
                                      (v71/*: any*/)
                                    ],
                                    "type": "Commit",
                                    "abstractKey": null
                                  },
                                  (v23/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v110/*: any*/)
                            ],
                            "type": "ClosedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v119/*: any*/),
                            "type": "ReopenedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "lockReason",
                                "storageKey": null
                              },
                              (v110/*: any*/)
                            ],
                            "type": "LockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v119/*: any*/),
                            "type": "UnlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v119/*: any*/),
                            "type": "PinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v119/*: any*/),
                            "type": "UnpinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v120/*: any*/),
                            "type": "LabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              (v110/*: any*/),
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
                            "selections": (v120/*: any*/),
                            "type": "UnlabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "actor",
                                "plural": false,
                                "selections": [
                                  (v13/*: any*/),
                                  (v16/*: any*/),
                                  (v109/*: any*/),
                                  (v19/*: any*/),
                                  (v18/*: any*/),
                                  (v21/*: any*/),
                                  (v15/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v123/*: any*/)
                            ],
                            "type": "UnassignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              (v110/*: any*/),
                              (v123/*: any*/)
                            ],
                            "type": "AssignedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              (v110/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "deletedCommentAuthor",
                                "plural": false,
                                "selections": (v30/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "CommentDeletedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v42/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "blockDuration",
                                "storageKey": null
                              },
                              (v110/*: any*/),
                              {
                                "alias": "blockedUser",
                                "args": null,
                                "concreteType": "User",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": [
                                  (v16/*: any*/),
                                  (v15/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "UserBlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v124/*: any*/),
                            "type": "MilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v124/*: any*/),
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
                              (v29/*: any*/),
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
                                      (v37/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  (v23/*: any*/)
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
                                  (v114/*: any*/),
                                  (v116/*: any*/),
                                  (v23/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v110/*: any*/)
                            ],
                            "type": "CrossReferencedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
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
                                  (v13/*: any*/),
                                  (v23/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v110/*: any*/),
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
                                  (v27/*: any*/),
                                  (v118/*: any*/),
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
                                          (v16/*: any*/),
                                          (v80/*: any*/),
                                          (v15/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v39/*: any*/),
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
                                            "selections": (v125/*: any*/),
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "CertificateAttributes",
                                            "kind": "LinkedField",
                                            "name": "subject",
                                            "plural": false,
                                            "selections": (v125/*: any*/),
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
                                      (v17/*: any*/),
                                      (v31/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "defaultBranch",
                                        "storageKey": null
                                      },
                                      (v15/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v15/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v42/*: any*/)
                            ],
                            "type": "ReferencedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v126/*: any*/),
                            "type": "ConnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v110/*: any*/),
                              (v42/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "fromRepository",
                                "plural": false,
                                "selections": [
                                  (v32/*: any*/),
                                  (v27/*: any*/),
                                  (v15/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "TransferredEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v126/*: any*/),
                            "type": "DisconnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v110/*: any*/),
                              (v42/*: any*/),
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
                                      (v15/*: any*/),
                                      (v33/*: any*/),
                                      (v127/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v33/*: any*/),
                                      (v15/*: any*/),
                                      (v127/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v23/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v128/*: any*/),
                              (v29/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUndo",
                                "storageKey": null
                              },
                              (v15/*: any*/),
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
                              (v110/*: any*/),
                              (v42/*: any*/),
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
                                    "selections": (v129/*: any*/),
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v129/*: any*/),
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v23/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v128/*: any*/),
                              (v29/*: any*/)
                            ],
                            "type": "UnmarkedAsDuplicateEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v110/*: any*/),
                              (v42/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Discussion",
                                "kind": "LinkedField",
                                "name": "discussion",
                                "plural": false,
                                "selections": [
                                  (v27/*: any*/),
                                  (v33/*: any*/),
                                  (v15/*: any*/)
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
                              (v29/*: any*/),
                              (v42/*: any*/),
                              (v110/*: any*/),
                              (v130/*: any*/)
                            ],
                            "type": "AddedToProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v42/*: any*/),
                              (v110/*: any*/),
                              (v130/*: any*/)
                            ],
                            "type": "RemovedFromProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v42/*: any*/),
                              (v110/*: any*/),
                              (v130/*: any*/),
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
                              (v42/*: any*/),
                              (v110/*: any*/),
                              (v29/*: any*/)
                            ],
                            "type": "ConvertedFromDraftEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v131/*: any*/),
                            "type": "SubIssueAddedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v131/*: any*/),
                            "type": "SubIssueRemovedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v133/*: any*/),
                            "type": "ParentIssueAddedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v133/*: any*/),
                            "type": "ParentIssueRemovedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v134/*: any*/),
                            "type": "IssueTypeAddedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v134/*: any*/),
                            "type": "IssueTypeRemovedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v29/*: any*/),
                              (v110/*: any*/),
                              (v42/*: any*/),
                              (v69/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "IssueType",
                                "kind": "LinkedField",
                                "name": "prevIssueType",
                                "plural": false,
                                "selections": (v68/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "IssueTypeChangedEvent",
                            "abstractKey": null
                          },
                          (v23/*: any*/),
                          (v14/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "filters": null,
                    "handle": "appendEdge",
                    "key": "",
                    "kind": "LinkedHandle",
                    "name": "edges",
                    "handleArgs": [
                      {
                        "kind": "Variable",
                        "name": "connections",
                        "variableName": "connections"
                      }
                    ]
                  }
                ],
                "storageKey": null
              },
              (v15/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "91d5eb4b023d9a0256c1a357fcfac031",
    "metadata": {},
    "name": "IssueViewerSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "97d5c31a1dbe998997dee071d73036d3";

export default node;
