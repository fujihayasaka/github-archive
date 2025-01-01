/**
 * @generated SignedSource<<d8ba99da290026c84dae200bc5bb0ecd>>
 * @relayHash 372be8ba76e0fed9f7190d4ef8332786
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 372be8ba76e0fed9f7190d4ef8332786

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueViewerSecondaryViewQuery$variables = {
  customisedNotificationsEnabled?: boolean | null | undefined;
  markAsRead?: boolean | null | undefined;
  number: number;
  owner: string;
  repo: string;
  useNewTimeline?: boolean | null | undefined;
};
export type IssueViewerSecondaryViewQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryViewQueryData">;
  } | null | undefined;
};
export type IssueViewerSecondaryViewQuery = {
  response: IssueViewerSecondaryViewQuery$data;
  variables: IssueViewerSecondaryViewQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": true,
  "kind": "LocalArgument",
  "name": "customisedNotificationsEnabled"
},
v1 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "markAsRead"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v5 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "useNewTimeline"
},
v6 = [
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
v7 = {
  "kind": "Variable",
  "name": "markAsRead",
  "variableName": "markAsRead"
},
v8 = {
  "kind": "Variable",
  "name": "number",
  "variableName": "number"
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
  "name": "number",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v12/*: any*/),
    (v13/*: any*/),
    (v9/*: any*/)
  ],
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v17 = {
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
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
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
  "name": "completed",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "concreteType": "SubIssuesSummary",
  "kind": "LinkedField",
  "name": "subIssuesSummary",
  "plural": false,
  "selections": [
    (v21/*: any*/)
  ],
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v24 = [
  (v23/*: any*/)
],
v25 = {
  "alias": "subIssuesConnection",
  "args": null,
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "subIssues",
  "plural": false,
  "selections": (v24/*: any*/),
  "storageKey": null
},
v26 = {
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
    (v9/*: any*/),
    (v12/*: any*/)
  ],
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestConnection",
  "kind": "LinkedField",
  "name": "associatedPullRequests",
  "plural": false,
  "selections": (v24/*: any*/),
  "storageKey": null
},
v28 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v29 = {
  "kind": "Literal",
  "name": "includeClosedPrs",
  "value": true
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v31 = [
  (v28/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueViewerSecondaryViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "customisedNotificationsEnabled",
                "variableName": "customisedNotificationsEnabled"
              },
              (v7/*: any*/),
              (v8/*: any*/),
              {
                "kind": "Variable",
                "name": "useNewTimeline",
                "variableName": "useNewTimeline"
              }
            ],
            "kind": "FragmentSpread",
            "name": "IssueViewerSecondaryViewQueryData"
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
      (v4/*: any*/),
      (v3/*: any*/),
      (v2/*: any*/),
      (v1/*: any*/),
      (v5/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "IssueViewerSecondaryViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": [
              (v7/*: any*/),
              (v8/*: any*/)
            ],
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isTransferInProgress",
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
                      (v14/*: any*/),
                      (v9/*: any*/),
                      (v15/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v16/*: any*/),
                  (v17/*: any*/),
                  (v18/*: any*/),
                  (v19/*: any*/),
                  (v20/*: any*/),
                  (v22/*: any*/),
                  (v25/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanReopen",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanClose",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Discussion",
                "kind": "LinkedField",
                "name": "discussion",
                "plural": false,
                "selections": [
                  (v20/*: any*/),
                  (v9/*: any*/)
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
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "slashCommandsEnabled",
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  (v11/*: any*/),
                  (v14/*: any*/),
                  (v15/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanPinIssues",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              (v9/*: any*/),
              (v18/*: any*/),
              (v10/*: any*/),
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
                      (v9/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Ref",
                        "kind": "LinkedField",
                        "name": "ref",
                        "plural": false,
                        "selections": [
                          (v11/*: any*/),
                          (v9/*: any*/),
                          (v12/*: any*/),
                          (v26/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": [
                              (v9/*: any*/),
                              (v15/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Ref",
                                "kind": "LinkedField",
                                "name": "defaultBranchRef",
                                "plural": false,
                                "selections": [
                                  (v11/*: any*/),
                                  (v9/*: any*/),
                                  (v26/*: any*/),
                                  (v27/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": [
                                      (v9/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          (v27/*: any*/)
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
                  (v28/*: any*/),
                  (v29/*: any*/)
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
                      (v9/*: any*/),
                      (v12/*: any*/),
                      (v20/*: any*/),
                      (v10/*: any*/),
                      (v18/*: any*/),
                      (v16/*: any*/),
                      (v30/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isInMergeQueue",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "createdAt",
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
                          (v11/*: any*/),
                          (v15/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "owner",
                            "plural": false,
                            "selections": [
                              (v13/*: any*/),
                              (v12/*: any*/),
                              (v9/*: any*/)
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
              {
                "alias": "linkedPullRequests",
                "args": [
                  (v28/*: any*/),
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
                          (v15/*: any*/),
                          (v9/*: any*/),
                          (v11/*: any*/),
                          (v14/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v16/*: any*/),
                      (v30/*: any*/),
                      (v20/*: any*/),
                      (v10/*: any*/),
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
                "kind": "ScalarField",
                "name": "viewerCanLinkBranches",
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
                "kind": "ScalarField",
                "name": "threadSubscriptionChannel",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerThreadSubscriptionFormAction",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v31/*: any*/),
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "participants",
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
                      (v13/*: any*/),
                      (v11/*: any*/),
                      {
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
                      }
                    ],
                    "storageKey": null
                  },
                  (v23/*: any*/)
                ],
                "storageKey": "participants(first:10)"
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
                "name": "viewerCanDelete",
                "storageKey": null
              },
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
                "name": "viewerCanType",
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
                "concreteType": "TaskListSummary",
                "kind": "LinkedField",
                "name": "taskListSummary",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "itemCount",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "completeCount",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "TrackedIssueCompletion",
                "kind": "LinkedField",
                "name": "tasklistBlocksCompletion",
                "plural": false,
                "selections": [
                  (v21/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "total",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v31/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "trackedInIssues",
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
                      (v10/*: any*/),
                      (v20/*: any*/),
                      (v17/*: any*/),
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v23/*: any*/)
                ],
                "storageKey": "trackedInIssues(first:10)"
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
                      (v9/*: any*/),
                      (v16/*: any*/),
                      (v17/*: any*/),
                      {
                        "alias": null,
                        "args": (v31/*: any*/),
                        "concreteType": "UserConnection",
                        "kind": "LinkedField",
                        "name": "assignees",
                        "plural": false,
                        "selections": [
                          (v23/*: any*/),
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
                                  (v9/*: any*/),
                                  (v13/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "avatarUrl",
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": "assignees(first:10)"
                      },
                      (v20/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v11/*: any*/),
                          (v14/*: any*/),
                          (v9/*: any*/)
                        ],
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "databaseId",
                        "storageKey": null
                      },
                      (v10/*: any*/),
                      (v18/*: any*/),
                      (v19/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "IssueType",
                        "kind": "LinkedField",
                        "name": "issueType",
                        "plural": false,
                        "selections": [
                          (v9/*: any*/),
                          (v11/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "color",
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      },
                      (v22/*: any*/),
                      (v25/*: any*/),
                      {
                        "alias": null,
                        "args": [
                          {
                            "kind": "Literal",
                            "name": "first",
                            "value": 0
                          },
                          (v29/*: any*/)
                        ],
                        "concreteType": "PullRequestConnection",
                        "kind": "LinkedField",
                        "name": "closedByPullRequestsReferences",
                        "plural": false,
                        "selections": (v24/*: any*/),
                        "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "closed",
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "subIssues(first:50)"
              },
              (v25/*: any*/),
              {
                "condition": "customisedNotificationsEnabled",
                "kind": "Condition",
                "passingValue": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCustomSubscriptionEvents",
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
                          (v20/*: any*/),
                          (v13/*: any*/),
                          (v9/*: any*/)
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
                    "kind": "ScalarField",
                    "name": "showSpammyBadge",
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "codeOfConductFileUrl",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "securityPolicyUrl",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "contributingFileUrl",
            "storageKey": null
          },
          (v9/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "372be8ba76e0fed9f7190d4ef8332786",
    "metadata": {},
    "name": "IssueViewerSecondaryViewQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e9e99595196088949f7f5739bbc1331c";

export default node;
