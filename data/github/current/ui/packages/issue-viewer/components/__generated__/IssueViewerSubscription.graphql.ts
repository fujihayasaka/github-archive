/**
 * @generated SignedSource<<92c16079a258083352558442b4c551cd>>
 * @relayHash 40261b9bb4fdcbb43f445c5646062f83
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 40261b9bb4fdcbb43f445c5646062f83

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
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionAssignees" | "LabelsSectionAssignedLabels" | "MilestonesSectionMilestone" | "ProjectsSectionFragment">;
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
      readonly " $fragmentSpreads": FragmentRefs<"HeaderIssueType">;
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
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v10 = [
  (v9/*: any*/),
  {
    "kind": "Literal",
    "name": "includeIssueTypeEvents",
    "value": true
  },
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
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v13 = {
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
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v17 = {
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
v18 = {
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
        (v14/*: any*/),
        (v15/*: any*/),
        (v16/*: any*/),
        (v17/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "assignees(first:20)"
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
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
  "concreteType": "Milestone",
  "kind": "LinkedField",
  "name": "milestone",
  "plural": false,
  "selections": [
    (v14/*: any*/),
    (v19/*: any*/),
    (v20/*: any*/),
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
    (v21/*: any*/),
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
v23 = {
  "kind": "Literal",
  "name": "first",
  "value": 100
},
v24 = [
  (v23/*: any*/),
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
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
  "name": "nameHTML",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v29 = {
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
    }
  ],
  "storageKey": null
},
v30 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": (v24/*: any*/),
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
                (v14/*: any*/),
                (v25/*: any*/),
                (v16/*: any*/),
                (v26/*: any*/),
                (v27/*: any*/),
                (v21/*: any*/),
                (v12/*: any*/)
              ],
              "storageKey": null
            },
            (v28/*: any*/)
          ],
          "storageKey": null
        },
        (v29/*: any*/)
      ],
      "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
    },
    {
      "alias": null,
      "args": (v24/*: any*/),
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
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v32 = [
  (v12/*: any*/),
  (v15/*: any*/),
  (v14/*: any*/)
],
v33 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": (v32/*: any*/),
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v16/*: any*/),
    (v33/*: any*/),
    (v34/*: any*/),
    (v14/*: any*/)
  ],
  "storageKey": null
},
v36 = [
  (v9/*: any*/)
],
v37 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v38 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v40 = [
  (v14/*: any*/)
],
v41 = {
  "kind": "InlineFragment",
  "selections": (v40/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v42 = {
  "alias": null,
  "args": (v36/*: any*/),
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
            (v14/*: any*/),
            (v34/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v14/*: any*/),
                (v19/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v37/*: any*/),
                (v21/*: any*/),
                {
                  "alias": null,
                  "args": (v38/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v12/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v14/*: any*/),
                        (v16/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v14/*: any*/),
                            (v39/*: any*/),
                            (v16/*: any*/),
                            (v26/*: any*/),
                            (v25/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v27/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v41/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v20/*: any*/),
                (v31/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v12/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v38/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v12/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v14/*: any*/),
                    (v39/*: any*/),
                    (v16/*: any*/),
                    (v26/*: any*/),
                    (v25/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v41/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v12/*: any*/)
          ],
          "storageKey": null
        },
        (v28/*: any*/)
      ],
      "storageKey": null
    },
    (v29/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v43 = {
  "alias": null,
  "args": (v36/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdateMetadata",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v46 = {
  "kind": "Literal",
  "name": "unfurlReferences",
  "value": true
},
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "bodyVersion",
  "storageKey": null
},
v48 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v49 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v50 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v51 = [
  (v16/*: any*/),
  (v25/*: any*/),
  (v14/*: any*/)
],
v52 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": (v51/*: any*/),
  "storageKey": null
},
v53 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v54 = {
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
v55 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v16/*: any*/),
    (v33/*: any*/),
    (v14/*: any*/)
  ],
  "storageKey": null
},
v56 = {
  "alias": null,
  "args": null,
  "concreteType": "Issue",
  "kind": "LinkedField",
  "name": "duplicateOf",
  "plural": false,
  "selections": [
    (v31/*: any*/),
    (v21/*: any*/),
    (v55/*: any*/),
    (v14/*: any*/)
  ],
  "storageKey": null
},
v57 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v48/*: any*/),
    (v14/*: any*/),
    (v16/*: any*/),
    (v33/*: any*/)
  ],
  "storageKey": null
},
v58 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v59 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "total",
  "storageKey": null
},
v60 = {
  "alias": null,
  "args": null,
  "concreteType": "SubIssuesSummary",
  "kind": "LinkedField",
  "name": "subIssuesSummary",
  "plural": false,
  "selections": [
    (v59/*: any*/),
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
v61 = [
  (v15/*: any*/)
],
v62 = {
  "kind": "InlineFragment",
  "selections": (v61/*: any*/),
  "type": "User",
  "abstractKey": null
},
v63 = {
  "kind": "InlineFragment",
  "selections": (v61/*: any*/),
  "type": "Bot",
  "abstractKey": null
},
v64 = {
  "kind": "InlineFragment",
  "selections": (v61/*: any*/),
  "type": "Organization",
  "abstractKey": null
},
v65 = {
  "kind": "InlineFragment",
  "selections": (v61/*: any*/),
  "type": "Mannequin",
  "abstractKey": null
},
v66 = {
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
            (v11/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                (v12/*: any*/),
                (v62/*: any*/),
                (v63/*: any*/),
                (v64/*: any*/),
                (v65/*: any*/),
                (v41/*: any*/)
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
v67 = [
  (v14/*: any*/),
  (v66/*: any*/)
],
v68 = {
  "alias": null,
  "args": [
    (v46/*: any*/)
  ],
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": "bodyHTML(unfurlReferences:true)"
},
v69 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v70 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v71 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
  "plural": false,
  "selections": (v32/*: any*/),
  "storageKey": null
},
v72 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v73 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "authorAssociation",
  "storageKey": null
},
v74 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanDelete",
  "storageKey": null
},
v75 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanMinimize",
  "storageKey": null
},
v76 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReport",
  "storageKey": null
},
v77 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanReportToMaintainer",
  "storageKey": null
},
v78 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanBlockFromOrg",
  "storageKey": null
},
v79 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUnblockFromOrg",
  "storageKey": null
},
v80 = {
  "alias": "isHidden",
  "args": null,
  "kind": "ScalarField",
  "name": "isMinimized",
  "storageKey": null
},
v81 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "minimizedReason",
  "storageKey": null
},
v82 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "showSpammyBadge",
  "storageKey": null
},
v83 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdViaEmail",
  "storageKey": null
},
v84 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerDidAuthor",
  "storageKey": null
},
v85 = {
  "alias": null,
  "args": null,
  "concreteType": "Sponsorship",
  "kind": "LinkedField",
  "name": "authorToRepoOwnerSponsorship",
  "plural": false,
  "selections": [
    (v72/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isActive",
      "storageKey": null
    },
    (v14/*: any*/)
  ],
  "storageKey": null
},
v86 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v14/*: any*/),
    (v15/*: any*/),
    (v21/*: any*/)
  ],
  "storageKey": null
},
v87 = {
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
            (v21/*: any*/),
            (v15/*: any*/),
            (v14/*: any*/)
          ],
          "storageKey": null
        },
        (v14/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
},
v88 = {
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
v89 = [
  (v11/*: any*/)
],
v90 = {
  "alias": null,
  "args": [
    (v23/*: any*/)
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
        (v14/*: any*/),
        (v53/*: any*/),
        (v54/*: any*/),
        {
          "alias": null,
          "args": (v36/*: any*/),
          "concreteType": "UserConnection",
          "kind": "LinkedField",
          "name": "assignees",
          "plural": false,
          "selections": [
            (v11/*: any*/),
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
                    (v14/*: any*/),
                    (v15/*: any*/),
                    (v69/*: any*/)
                  ],
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": "assignees(first:10)"
        },
        (v21/*: any*/),
        (v55/*: any*/),
        (v70/*: any*/),
        (v31/*: any*/),
        (v19/*: any*/),
        (v50/*: any*/),
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueType",
          "kind": "LinkedField",
          "name": "issueType",
          "plural": false,
          "selections": [
            (v14/*: any*/),
            (v16/*: any*/),
            (v25/*: any*/)
          ],
          "storageKey": null
        },
        (v60/*: any*/),
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 0
            },
            {
              "kind": "Literal",
              "name": "includeClosedPrs",
              "value": true
            }
          ],
          "concreteType": "PullRequestConnection",
          "kind": "LinkedField",
          "name": "closedByPullRequestsReferences",
          "plural": false,
          "selections": (v89/*: any*/),
          "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
        },
        (v20/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": "subIssues(first:100)"
},
v91 = {
  "alias": "subIssuesConnection",
  "args": null,
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "subIssues",
  "plural": false,
  "selections": (v89/*: any*/),
  "storageKey": null
},
v92 = {
  "alias": null,
  "args": null,
  "concreteType": "Issue",
  "kind": "LinkedField",
  "name": "parent",
  "plural": false,
  "selections": (v40/*: any*/),
  "storageKey": null
},
v93 = {
  "alias": null,
  "args": null,
  "concreteType": "SubIssuesSummary",
  "kind": "LinkedField",
  "name": "subIssuesSummary",
  "plural": false,
  "selections": [
    (v59/*: any*/)
  ],
  "storageKey": null
},
v94 = {
  "kind": "TypeDiscriminator",
  "abstractKey": "__isActor"
},
v95 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "actor",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v94/*: any*/),
    (v17/*: any*/),
    (v15/*: any*/),
    (v14/*: any*/)
  ],
  "storageKey": null
},
v96 = [
  (v72/*: any*/),
  (v70/*: any*/),
  (v95/*: any*/)
],
v97 = {
  "alias": "issueTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v98 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v14/*: any*/),
    (v16/*: any*/),
    (v49/*: any*/),
    (v33/*: any*/)
  ],
  "storageKey": null
},
v99 = {
  "kind": "InlineFragment",
  "selections": [
    (v14/*: any*/),
    (v97/*: any*/),
    (v21/*: any*/),
    (v31/*: any*/),
    (v54/*: any*/),
    (v98/*: any*/)
  ],
  "type": "Issue",
  "abstractKey": null
},
v100 = {
  "alias": "pullTitleHTML",
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v101 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInMergeQueue",
  "storageKey": null
},
v102 = {
  "kind": "InlineFragment",
  "selections": [
    (v14/*: any*/),
    (v100/*: any*/),
    (v21/*: any*/),
    (v31/*: any*/),
    (v53/*: any*/),
    (v58/*: any*/),
    (v101/*: any*/),
    (v98/*: any*/)
  ],
  "type": "PullRequest",
  "abstractKey": null
},
v103 = {
  "kind": "InlineFragment",
  "selections": [
    (v99/*: any*/),
    (v102/*: any*/)
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v104 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "abbreviatedOid",
  "storageKey": null
},
v105 = [
  (v70/*: any*/),
  (v72/*: any*/),
  (v95/*: any*/)
],
v106 = [
  (v70/*: any*/),
  (v72/*: any*/),
  (v95/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Label",
    "kind": "LinkedField",
    "name": "label",
    "plural": false,
    "selections": [
      (v26/*: any*/),
      (v16/*: any*/),
      (v25/*: any*/),
      (v14/*: any*/),
      (v27/*: any*/)
    ],
    "storageKey": null
  }
],
v107 = [
  (v70/*: any*/),
  (v72/*: any*/),
  (v95/*: any*/),
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
      (v21/*: any*/),
      (v14/*: any*/)
    ],
    "storageKey": null
  }
],
v108 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": (v40/*: any*/),
  "storageKey": null
},
v109 = [
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
v110 = [
  (v70/*: any*/),
  (v95/*: any*/),
  (v72/*: any*/),
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
          (v19/*: any*/),
          (v21/*: any*/),
          (v31/*: any*/),
          (v53/*: any*/),
          (v58/*: any*/),
          (v101/*: any*/),
          (v55/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      },
      (v41/*: any*/)
    ],
    "storageKey": null
  }
],
v111 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v97/*: any*/),
        (v21/*: any*/),
        (v54/*: any*/),
        (v98/*: any*/)
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v100/*: any*/),
        (v21/*: any*/),
        (v53/*: any*/),
        (v58/*: any*/),
        (v101/*: any*/),
        (v98/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "ReferencedSubject",
  "abstractKey": "__isReferencedSubject"
},
v112 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isCanonicalOfClosedDuplicate",
  "storageKey": null
},
v113 = [
  (v103/*: any*/)
],
v114 = {
  "alias": null,
  "args": null,
  "concreteType": "ProjectV2",
  "kind": "LinkedField",
  "name": "project",
  "plural": false,
  "selections": [
    (v19/*: any*/),
    (v21/*: any*/),
    (v14/*: any*/)
  ],
  "storageKey": null
},
v115 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v16/*: any*/),
    (v49/*: any*/),
    (v33/*: any*/)
  ],
  "storageKey": null
},
v116 = [
  (v108/*: any*/),
  (v70/*: any*/),
  (v14/*: any*/),
  {
    "kind": "InlineFragment",
    "selections": [
      (v12/*: any*/),
      {
        "kind": "InlineFragment",
        "selections": [
          (v97/*: any*/),
          (v21/*: any*/),
          (v31/*: any*/),
          (v54/*: any*/),
          (v115/*: any*/)
        ],
        "type": "Issue",
        "abstractKey": null
      },
      {
        "kind": "InlineFragment",
        "selections": [
          (v100/*: any*/),
          (v21/*: any*/),
          (v31/*: any*/),
          (v53/*: any*/),
          (v58/*: any*/),
          (v101/*: any*/),
          (v115/*: any*/)
        ],
        "type": "PullRequest",
        "abstractKey": null
      }
    ],
    "type": "ReferencedSubject",
    "abstractKey": "__isReferencedSubject"
  }
],
v117 = [
  (v70/*: any*/),
  (v95/*: any*/),
  (v72/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "subIssue",
    "plural": false,
    "selections": (v116/*: any*/),
    "storageKey": null
  }
],
v118 = [
  (v70/*: any*/),
  (v95/*: any*/),
  (v72/*: any*/),
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "parent",
    "plural": false,
    "selections": (v116/*: any*/),
    "storageKey": null
  }
],
v119 = [
  (v70/*: any*/),
  (v95/*: any*/),
  (v72/*: any*/),
  (v52/*: any*/)
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
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "RelationshipsSectionFragment"
              },
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
            "name": "issueTimelineUpdated",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": (v10/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v11/*: any*/),
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
                          (v13/*: any*/)
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
              (v18/*: any*/),
              (v22/*: any*/),
              (v14/*: any*/),
              (v30/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v31/*: any*/),
                      (v35/*: any*/),
                      (v42/*: any*/),
                      (v43/*: any*/),
                      (v44/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v31/*: any*/),
                      (v35/*: any*/),
                      (v42/*: any*/),
                      (v43/*: any*/),
                      (v37/*: any*/)
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
              (v45/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "renderTasklistBlocks",
                    "value": true
                  },
                  (v46/*: any*/)
                ],
                "kind": "ScalarField",
                "name": "bodyHTML",
                "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
              },
              (v47/*: any*/),
              (v14/*: any*/)
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
              (v19/*: any*/),
              (v31/*: any*/),
              (v14/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v48/*: any*/),
                  (v14/*: any*/),
                  (v16/*: any*/),
                  (v33/*: any*/),
                  (v34/*: any*/),
                  (v49/*: any*/)
                ],
                "storageKey": null
              },
              (v50/*: any*/),
              (v21/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateNext",
                "storageKey": null
              },
              (v52/*: any*/),
              (v53/*: any*/),
              (v54/*: any*/),
              (v56/*: any*/),
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v9/*: any*/),
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
                      (v57/*: any*/),
                      (v53/*: any*/),
                      (v58/*: any*/),
                      (v21/*: any*/),
                      (v31/*: any*/),
                      (v14/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "closedByPullRequestsReferences(first:10,includeClosedPrs:false,orderByState:true)"
              },
              (v60/*: any*/),
              (v18/*: any*/),
              (v22/*: any*/),
              (v30/*: any*/)
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
              (v53/*: any*/),
              (v54/*: any*/),
              (v56/*: any*/),
              (v14/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v14/*: any*/),
                  (v48/*: any*/),
                  (v33/*: any*/)
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
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v48/*: any*/),
                  (v14/*: any*/)
                ],
                "storageKey": null
              },
              (v52/*: any*/),
              (v14/*: any*/)
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
            "selections": (v67/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueComment",
            "kind": "LinkedField",
            "name": "commentReactionUpdated",
            "plural": false,
            "selections": (v67/*: any*/),
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
              (v14/*: any*/),
              (v45/*: any*/),
              (v68/*: any*/),
              (v47/*: any*/),
              (v37/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "author",
                "plural": false,
                "selections": [
                  (v12/*: any*/),
                  (v15/*: any*/),
                  (v69/*: any*/),
                  (v14/*: any*/)
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
                  (v14/*: any*/),
                  (v70/*: any*/),
                  (v71/*: any*/),
                  (v31/*: any*/)
                ],
                "storageKey": null
              },
              (v70/*: any*/),
              (v21/*: any*/),
              (v72/*: any*/),
              (v73/*: any*/),
              (v74/*: any*/),
              (v75/*: any*/),
              (v76/*: any*/),
              (v77/*: any*/),
              (v78/*: any*/),
              (v79/*: any*/),
              (v80/*: any*/),
              (v81/*: any*/),
              (v82/*: any*/),
              (v83/*: any*/),
              (v84/*: any*/),
              (v85/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v14/*: any*/),
                  (v16/*: any*/),
                  (v86/*: any*/),
                  (v49/*: any*/)
                ],
                "storageKey": null
              },
              (v87/*: any*/),
              (v88/*: any*/)
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
              (v14/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v16/*: any*/),
                  (v14/*: any*/),
                  (v48/*: any*/),
                  (v33/*: any*/)
                ],
                "storageKey": null
              },
              (v90/*: any*/),
              (v91/*: any*/),
              (v92/*: any*/),
              (v93/*: any*/)
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
              (v14/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v16/*: any*/),
                  (v14/*: any*/),
                  (v48/*: any*/),
                  (v33/*: any*/),
                  (v34/*: any*/)
                ],
                "storageKey": null
              },
              (v90/*: any*/),
              (v91/*: any*/),
              (v92/*: any*/),
              (v93/*: any*/),
              (v44/*: any*/)
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
              (v14/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v48/*: any*/),
                  (v33/*: any*/),
                  (v14/*: any*/),
                  (v34/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Issue",
                "kind": "LinkedField",
                "name": "parent",
                "plural": false,
                "selections": [
                  (v14/*: any*/),
                  (v19/*: any*/),
                  (v50/*: any*/),
                  (v21/*: any*/),
                  (v31/*: any*/),
                  (v57/*: any*/),
                  (v53/*: any*/),
                  (v54/*: any*/),
                  (v60/*: any*/)
                ],
                "storageKey": null
              },
              (v44/*: any*/)
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
                "args": (v10/*: any*/),
                "concreteType": "IssueTimelineItemsConnection",
                "kind": "LinkedField",
                "name": "timelineItems",
                "plural": false,
                "selections": [
                  (v11/*: any*/),
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
                          {
                            "kind": "InlineFragment",
                            "selections": (v96/*: any*/),
                            "type": "SubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v96/*: any*/),
                            "type": "UnsubscribedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v96/*: any*/),
                            "type": "MentionedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v14/*: any*/),
                              (v70/*: any*/),
                              (v45/*: any*/),
                              (v68/*: any*/),
                              (v47/*: any*/),
                              (v37/*: any*/),
                              (v21/*: any*/),
                              (v72/*: any*/),
                              (v73/*: any*/),
                              (v74/*: any*/),
                              (v75/*: any*/),
                              (v76/*: any*/),
                              (v77/*: any*/),
                              (v78/*: any*/),
                              (v79/*: any*/),
                              (v80/*: any*/),
                              (v81/*: any*/),
                              (v82/*: any*/),
                              (v83/*: any*/),
                              (v84/*: any*/),
                              (v85/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "author",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  (v14/*: any*/),
                                  (v15/*: any*/),
                                  (v69/*: any*/)
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
                                  (v14/*: any*/),
                                  (v16/*: any*/),
                                  (v86/*: any*/),
                                  (v49/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slashCommandsEnabled",
                                    "storageKey": null
                                  },
                                  (v48/*: any*/),
                                  (v70/*: any*/)
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
                                  (v31/*: any*/),
                                  (v14/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "locked",
                                    "storageKey": null
                                  },
                                  (v70/*: any*/),
                                  (v71/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v87/*: any*/),
                              (v88/*: any*/),
                              (v66/*: any*/)
                            ],
                            "type": "IssueComment",
                            "abstractKey": null
                          },
                          (v66/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v72/*: any*/),
                              (v54/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "duplicateOf",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  (v103/*: any*/),
                                  (v41/*: any*/)
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
                                      (v21/*: any*/),
                                      (v19/*: any*/)
                                    ],
                                    "type": "ProjectV2",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v21/*: any*/),
                                      (v31/*: any*/),
                                      (v55/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v21/*: any*/),
                                      (v104/*: any*/),
                                      (v55/*: any*/)
                                    ],
                                    "type": "Commit",
                                    "abstractKey": null
                                  },
                                  (v41/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v95/*: any*/)
                            ],
                            "type": "ClosedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v105/*: any*/),
                            "type": "ReopenedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v72/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "lockReason",
                                "storageKey": null
                              },
                              (v95/*: any*/)
                            ],
                            "type": "LockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v105/*: any*/),
                            "type": "UnlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v105/*: any*/),
                            "type": "PinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v105/*: any*/),
                            "type": "UnpinnedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v106/*: any*/),
                            "type": "LabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v72/*: any*/),
                              (v95/*: any*/),
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
                            "selections": (v106/*: any*/),
                            "type": "UnlabeledEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v72/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "actor",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  (v15/*: any*/),
                                  (v94/*: any*/),
                                  (v17/*: any*/),
                                  (v14/*: any*/)
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
                                  (v12/*: any*/),
                                  (v62/*: any*/),
                                  (v65/*: any*/),
                                  (v64/*: any*/),
                                  (v63/*: any*/),
                                  (v41/*: any*/)
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
                              (v70/*: any*/),
                              (v72/*: any*/),
                              (v95/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "assignee",
                                "plural": false,
                                "selections": [
                                  (v12/*: any*/),
                                  (v62/*: any*/),
                                  (v65/*: any*/),
                                  (v64/*: any*/),
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v15/*: any*/),
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
                                  (v41/*: any*/)
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
                              (v70/*: any*/),
                              (v72/*: any*/),
                              (v95/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": null,
                                "kind": "LinkedField",
                                "name": "deletedCommentAuthor",
                                "plural": false,
                                "selections": (v32/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "CommentDeletedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v72/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "blockDuration",
                                "storageKey": null
                              },
                              (v95/*: any*/),
                              {
                                "alias": "blockedUser",
                                "args": null,
                                "concreteType": "User",
                                "kind": "LinkedField",
                                "name": "subject",
                                "plural": false,
                                "selections": [
                                  (v15/*: any*/),
                                  (v14/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "UserBlockedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v107/*: any*/),
                            "type": "MilestonedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v107/*: any*/),
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
                              (v70/*: any*/),
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
                                      (v108/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  (v41/*: any*/)
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
                                  (v99/*: any*/),
                                  (v102/*: any*/),
                                  (v41/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v95/*: any*/)
                            ],
                            "type": "CrossReferencedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
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
                                  (v12/*: any*/),
                                  (v41/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v95/*: any*/),
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
                                  (v104/*: any*/),
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
                                          (v15/*: any*/),
                                          (v69/*: any*/),
                                          (v14/*: any*/)
                                        ],
                                        "storageKey": null
                                      },
                                      (v53/*: any*/),
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
                                            "selections": (v109/*: any*/),
                                            "storageKey": null
                                          },
                                          {
                                            "alias": null,
                                            "args": null,
                                            "concreteType": "CertificateAttributes",
                                            "kind": "LinkedField",
                                            "name": "subject",
                                            "plural": false,
                                            "selections": (v109/*: any*/),
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
                                      (v16/*: any*/),
                                      (v33/*: any*/),
                                      {
                                        "alias": null,
                                        "args": null,
                                        "kind": "ScalarField",
                                        "name": "defaultBranch",
                                        "storageKey": null
                                      },
                                      (v14/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  (v14/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v72/*: any*/)
                            ],
                            "type": "ReferencedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v110/*: any*/),
                            "type": "ConnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v95/*: any*/),
                              (v72/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Repository",
                                "kind": "LinkedField",
                                "name": "fromRepository",
                                "plural": false,
                                "selections": [
                                  (v48/*: any*/),
                                  (v21/*: any*/),
                                  (v14/*: any*/)
                                ],
                                "storageKey": null
                              }
                            ],
                            "type": "TransferredEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v110/*: any*/),
                            "type": "DisconnectedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v95/*: any*/),
                              (v72/*: any*/),
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
                                      (v14/*: any*/),
                                      (v31/*: any*/),
                                      (v111/*: any*/)
                                    ],
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": [
                                      (v31/*: any*/),
                                      (v14/*: any*/),
                                      (v111/*: any*/)
                                    ],
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v41/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v112/*: any*/),
                              (v70/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "viewerCanUndo",
                                "storageKey": null
                              },
                              (v14/*: any*/),
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
                              (v95/*: any*/),
                              (v72/*: any*/),
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
                                    "selections": (v113/*: any*/),
                                    "type": "Issue",
                                    "abstractKey": null
                                  },
                                  {
                                    "kind": "InlineFragment",
                                    "selections": (v113/*: any*/),
                                    "type": "PullRequest",
                                    "abstractKey": null
                                  },
                                  (v41/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v112/*: any*/),
                              (v70/*: any*/)
                            ],
                            "type": "UnmarkedAsDuplicateEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v95/*: any*/),
                              (v72/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Discussion",
                                "kind": "LinkedField",
                                "name": "discussion",
                                "plural": false,
                                "selections": [
                                  (v21/*: any*/),
                                  (v31/*: any*/),
                                  (v14/*: any*/)
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
                              (v70/*: any*/),
                              (v72/*: any*/),
                              (v95/*: any*/),
                              (v114/*: any*/)
                            ],
                            "type": "AddedToProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v72/*: any*/),
                              (v95/*: any*/),
                              (v114/*: any*/)
                            ],
                            "type": "RemovedFromProjectV2Event",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v72/*: any*/),
                              (v95/*: any*/),
                              (v114/*: any*/),
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
                              (v72/*: any*/),
                              (v95/*: any*/),
                              (v70/*: any*/)
                            ],
                            "type": "ConvertedFromDraftEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v117/*: any*/),
                            "type": "SubIssueAddedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v117/*: any*/),
                            "type": "SubIssueRemovedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v118/*: any*/),
                            "type": "ParentIssueAddedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v118/*: any*/),
                            "type": "ParentIssueRemovedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v119/*: any*/),
                            "type": "IssueTypeAddedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v119/*: any*/),
                            "type": "IssueTypeRemovedEvent",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v70/*: any*/),
                              (v95/*: any*/),
                              (v72/*: any*/),
                              (v52/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "IssueType",
                                "kind": "LinkedField",
                                "name": "prevIssueType",
                                "plural": false,
                                "selections": (v51/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "type": "IssueTypeChangedEvent",
                            "abstractKey": null
                          },
                          (v41/*: any*/),
                          (v13/*: any*/)
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
              (v14/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "40261b9bb4fdcbb43f445c5646062f83",
    "metadata": {},
    "name": "IssueViewerSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "12529b130e23f70e633050991d392c3e";

export default node;
