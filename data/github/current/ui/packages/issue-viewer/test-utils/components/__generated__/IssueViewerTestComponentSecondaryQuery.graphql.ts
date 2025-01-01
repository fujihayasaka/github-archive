/**
 * @generated SignedSource<<3157205679df629e8f518c7dda78951e>>
 * @relayHash de03c4fd44e6e8e44755a9e3f176da00
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID de03c4fd44e6e8e44755a9e3f176da00

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerTestComponentSecondaryQuery$variables = {
  issueId: string;
};
export type IssueViewerTestComponentSecondaryQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryIssueData">;
  } | null | undefined;
};
export type IssueViewerTestComponentSecondaryQuery = {
  response: IssueViewerTestComponentSecondaryQuery$data;
  variables: IssueViewerTestComponentSecondaryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "issueId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "issueId"
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
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
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
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v6/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v10 = {
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
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "total",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "completed",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "concreteType": "SubIssuesSummary",
  "kind": "LinkedField",
  "name": "subIssuesSummary",
  "plural": false,
  "selections": [
    (v14/*: any*/),
    (v15/*: any*/)
  ],
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v18 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v19 = {
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
    (v3/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v21 = [
  (v20/*: any*/)
],
v22 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestConnection",
  "kind": "LinkedField",
  "name": "associatedPullRequests",
  "plural": false,
  "selections": (v21/*: any*/),
  "storageKey": null
},
v23 = {
  "kind": "Literal",
  "name": "includeClosedPrs",
  "value": true
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v25 = [
  (v18/*: any*/)
],
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v27 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v28 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v34 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v36 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v37 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v38 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v39 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v40 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v41 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v42 = {
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
v43 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "SubIssuesSummary"
},
v44 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v45 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v46 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v47 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v48 = {
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
    "name": "IssueViewerTestComponentSecondaryQuery",
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
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueViewerSecondaryIssueData"
              }
            ],
            "type": "Issue",
            "abstractKey": null
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
    "name": "IssueViewerTestComponentSecondaryQuery",
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
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
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
                  (v3/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "repository",
                    "plural": false,
                    "selections": [
                      (v5/*: any*/),
                      (v7/*: any*/),
                      (v3/*: any*/),
                      (v8/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/),
                  (v12/*: any*/),
                  (v13/*: any*/),
                  (v16/*: any*/)
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
                  (v13/*: any*/),
                  (v3/*: any*/)
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
                  (v3/*: any*/),
                  (v17/*: any*/),
                  (v5/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
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
                  },
                  {
                    "alias": null,
                    "args": [
                      (v18/*: any*/),
                      {
                        "kind": "Literal",
                        "name": "isAssignable",
                        "value": true
                      }
                    ],
                    "concreteType": "InstalledAppInstallationsConnection",
                    "kind": "LinkedField",
                    "name": "installedAppInstallations",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "IntegrationInstallationEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "IntegrationInstallation",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": [
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "App",
                                "kind": "LinkedField",
                                "name": "app",
                                "plural": false,
                                "selections": [
                                  (v3/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slug",
                                    "storageKey": null
                                  },
                                  (v5/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v3/*: any*/)
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "installedAppInstallations(first:10,isAssignable:true)"
                  }
                ],
                "storageKey": null
              },
              (v11/*: any*/),
              (v4/*: any*/),
              (v17/*: any*/),
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
                      (v3/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Ref",
                        "kind": "LinkedField",
                        "name": "ref",
                        "plural": false,
                        "selections": [
                          (v5/*: any*/),
                          (v3/*: any*/),
                          (v2/*: any*/),
                          (v19/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "Repository",
                            "kind": "LinkedField",
                            "name": "repository",
                            "plural": false,
                            "selections": [
                              (v3/*: any*/),
                              (v8/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "Ref",
                                "kind": "LinkedField",
                                "name": "defaultBranchRef",
                                "plural": false,
                                "selections": [
                                  (v5/*: any*/),
                                  (v3/*: any*/),
                                  (v19/*: any*/),
                                  (v22/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": [
                                      (v3/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          (v22/*: any*/)
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
                  (v18/*: any*/),
                  (v23/*: any*/)
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
                      (v3/*: any*/),
                      (v2/*: any*/),
                      (v13/*: any*/),
                      (v4/*: any*/),
                      (v11/*: any*/),
                      (v9/*: any*/),
                      (v24/*: any*/),
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
                          (v3/*: any*/),
                          (v5/*: any*/),
                          (v8/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "owner",
                            "plural": false,
                            "selections": [
                              (v6/*: any*/),
                              (v2/*: any*/),
                              (v3/*: any*/)
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
                  (v18/*: any*/),
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
                          (v8/*: any*/),
                          (v3/*: any*/),
                          (v5/*: any*/),
                          (v7/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v9/*: any*/),
                      (v24/*: any*/),
                      (v13/*: any*/),
                      (v4/*: any*/),
                      (v3/*: any*/)
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
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCustomSubscriptionEvents",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v25/*: any*/),
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
                      (v3/*: any*/),
                      (v6/*: any*/),
                      (v5/*: any*/),
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
                  (v20/*: any*/)
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
                  (v15/*: any*/),
                  (v14/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v25/*: any*/),
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
                      (v4/*: any*/),
                      (v13/*: any*/),
                      (v10/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v20/*: any*/)
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
                    "value": 100
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
                      (v3/*: any*/),
                      (v9/*: any*/),
                      (v10/*: any*/),
                      {
                        "alias": null,
                        "args": (v25/*: any*/),
                        "concreteType": "UserConnection",
                        "kind": "LinkedField",
                        "name": "assignees",
                        "plural": false,
                        "selections": [
                          (v20/*: any*/),
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
                                  (v3/*: any*/),
                                  (v6/*: any*/),
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
                      (v13/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "repository",
                        "plural": false,
                        "selections": [
                          (v5/*: any*/),
                          (v7/*: any*/),
                          (v3/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v17/*: any*/),
                      (v4/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "IssueType",
                        "kind": "LinkedField",
                        "name": "issueType",
                        "plural": false,
                        "selections": [
                          (v3/*: any*/),
                          (v5/*: any*/),
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
                      (v16/*: any*/),
                      {
                        "alias": null,
                        "args": [
                          {
                            "kind": "Literal",
                            "name": "first",
                            "value": 0
                          },
                          (v23/*: any*/)
                        ],
                        "concreteType": "PullRequestConnection",
                        "kind": "LinkedField",
                        "name": "closedByPullRequestsReferences",
                        "plural": false,
                        "selections": (v21/*: any*/),
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
                "storageKey": "subIssues(first:100)"
              },
              {
                "alias": "subIssuesConnection",
                "args": null,
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "subIssues",
                "plural": false,
                "selections": (v21/*: any*/),
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
                          (v13/*: any*/),
                          (v6/*: any*/),
                          (v3/*: any*/)
                        ],
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
                    "name": "showSpammyBadge",
                    "storageKey": null
                  }
                ],
                "type": "Comment",
                "abstractKey": "__isComment"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "de03c4fd44e6e8e44755a9e3f176da00",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isComment": (v26/*: any*/),
        "node.__typename": (v26/*: any*/),
        "node.closedByPullRequestsReferences": (v27/*: any*/),
        "node.closedByPullRequestsReferences.nodes": (v28/*: any*/),
        "node.closedByPullRequestsReferences.nodes.__typename": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.closedByPullRequestsReferences.nodes.id": (v29/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isDraft": (v30/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isInMergeQueue": (v30/*: any*/),
        "node.closedByPullRequestsReferences.nodes.number": (v31/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository": (v32/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.id": (v29/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.name": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner": (v33/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.id": (v29/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.login": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.state": (v34/*: any*/),
        "node.closedByPullRequestsReferences.nodes.title": (v26/*: any*/),
        "node.closedByPullRequestsReferences.nodes.url": (v35/*: any*/),
        "node.databaseId": (v36/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v29/*: any*/),
        "node.discussion.url": (v35/*: any*/),
        "node.id": (v29/*: any*/),
        "node.isTransferInProgress": (v30/*: any*/),
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
        "node.lastUserContentEdit.editor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "node.lastUserContentEdit.editor.__typename": (v26/*: any*/),
        "node.lastUserContentEdit.editor.id": (v29/*: any*/),
        "node.lastUserContentEdit.editor.login": (v26/*: any*/),
        "node.lastUserContentEdit.editor.url": (v35/*: any*/),
        "node.lastUserContentEdit.id": (v29/*: any*/),
        "node.linkedBranches": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "LinkedBranchConnection"
        },
        "node.linkedBranches.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LinkedBranch"
        },
        "node.linkedBranches.nodes.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref": (v37/*: any*/),
        "node.linkedBranches.nodes.ref.__typename": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests": (v38/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.name": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository": (v32/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef": (v37/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v38/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v31/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v32/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v40/*: any*/),
        "node.linkedBranches.nodes.ref.repository.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.repository.nameWithOwner": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.target": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.target.__typename": (v26/*: any*/),
        "node.linkedBranches.nodes.ref.target.id": (v29/*: any*/),
        "node.linkedBranches.nodes.ref.target.oid": (v40/*: any*/),
        "node.linkedPullRequests": (v27/*: any*/),
        "node.linkedPullRequests.nodes": (v28/*: any*/),
        "node.linkedPullRequests.nodes.id": (v29/*: any*/),
        "node.linkedPullRequests.nodes.isDraft": (v30/*: any*/),
        "node.linkedPullRequests.nodes.number": (v31/*: any*/),
        "node.linkedPullRequests.nodes.repository": (v32/*: any*/),
        "node.linkedPullRequests.nodes.repository.id": (v29/*: any*/),
        "node.linkedPullRequests.nodes.repository.name": (v26/*: any*/),
        "node.linkedPullRequests.nodes.repository.nameWithOwner": (v26/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner": (v33/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.__typename": (v26/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.id": (v29/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.login": (v26/*: any*/),
        "node.linkedPullRequests.nodes.state": (v34/*: any*/),
        "node.linkedPullRequests.nodes.url": (v35/*: any*/),
        "node.number": (v31/*: any*/),
        "node.parent": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "node.parent.id": (v29/*: any*/),
        "node.parent.number": (v31/*: any*/),
        "node.parent.repository": (v32/*: any*/),
        "node.parent.repository.id": (v29/*: any*/),
        "node.parent.repository.name": (v26/*: any*/),
        "node.parent.repository.nameWithOwner": (v26/*: any*/),
        "node.parent.repository.owner": (v33/*: any*/),
        "node.parent.repository.owner.__typename": (v26/*: any*/),
        "node.parent.repository.owner.id": (v29/*: any*/),
        "node.parent.repository.owner.login": (v26/*: any*/),
        "node.parent.state": (v41/*: any*/),
        "node.parent.stateReason": (v42/*: any*/),
        "node.parent.subIssuesSummary": (v43/*: any*/),
        "node.parent.subIssuesSummary.completed": (v31/*: any*/),
        "node.parent.subIssuesSummary.total": (v31/*: any*/),
        "node.parent.title": (v26/*: any*/),
        "node.parent.titleHTML": (v26/*: any*/),
        "node.parent.url": (v35/*: any*/),
        "node.participants": (v44/*: any*/),
        "node.participants.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "node.participants.nodes.avatarUrl": (v35/*: any*/),
        "node.participants.nodes.id": (v29/*: any*/),
        "node.participants.nodes.login": (v26/*: any*/),
        "node.participants.nodes.name": (v45/*: any*/),
        "node.participants.totalCount": (v31/*: any*/),
        "node.repository": (v32/*: any*/),
        "node.repository.databaseId": (v36/*: any*/),
        "node.repository.id": (v29/*: any*/),
        "node.repository.installedAppInstallations": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "InstalledAppInstallationsConnection"
        },
        "node.repository.installedAppInstallations.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IntegrationInstallationEdge"
        },
        "node.repository.installedAppInstallations.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IntegrationInstallation"
        },
        "node.repository.installedAppInstallations.edges.node.app": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "App"
        },
        "node.repository.installedAppInstallations.edges.node.app.id": (v29/*: any*/),
        "node.repository.installedAppInstallations.edges.node.app.name": (v26/*: any*/),
        "node.repository.installedAppInstallations.edges.node.app.slug": (v26/*: any*/),
        "node.repository.installedAppInstallations.edges.node.id": (v29/*: any*/),
        "node.repository.isArchived": (v30/*: any*/),
        "node.repository.name": (v26/*: any*/),
        "node.repository.nameWithOwner": (v26/*: any*/),
        "node.repository.owner": (v33/*: any*/),
        "node.repository.owner.__typename": (v26/*: any*/),
        "node.repository.owner.id": (v29/*: any*/),
        "node.repository.owner.login": (v26/*: any*/),
        "node.repository.slashCommandsEnabled": (v30/*: any*/),
        "node.repository.viewerCanPinIssues": (v30/*: any*/),
        "node.showSpammyBadge": (v30/*: any*/),
        "node.subIssues": (v46/*: any*/),
        "node.subIssues.nodes": (v47/*: any*/),
        "node.subIssues.nodes.assignees": (v44/*: any*/),
        "node.subIssues.nodes.assignees.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "UserEdge"
        },
        "node.subIssues.nodes.assignees.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "User"
        },
        "node.subIssues.nodes.assignees.edges.node.avatarUrl": (v35/*: any*/),
        "node.subIssues.nodes.assignees.edges.node.id": (v29/*: any*/),
        "node.subIssues.nodes.assignees.edges.node.login": (v26/*: any*/),
        "node.subIssues.nodes.assignees.totalCount": (v31/*: any*/),
        "node.subIssues.nodes.closed": (v30/*: any*/),
        "node.subIssues.nodes.closedByPullRequestsReferences": (v27/*: any*/),
        "node.subIssues.nodes.closedByPullRequestsReferences.totalCount": (v31/*: any*/),
        "node.subIssues.nodes.databaseId": (v36/*: any*/),
        "node.subIssues.nodes.id": (v29/*: any*/),
        "node.subIssues.nodes.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "node.subIssues.nodes.issueType.color": {
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
        "node.subIssues.nodes.issueType.id": (v29/*: any*/),
        "node.subIssues.nodes.issueType.name": (v26/*: any*/),
        "node.subIssues.nodes.number": (v31/*: any*/),
        "node.subIssues.nodes.repository": (v32/*: any*/),
        "node.subIssues.nodes.repository.id": (v29/*: any*/),
        "node.subIssues.nodes.repository.name": (v26/*: any*/),
        "node.subIssues.nodes.repository.owner": (v33/*: any*/),
        "node.subIssues.nodes.repository.owner.__typename": (v26/*: any*/),
        "node.subIssues.nodes.repository.owner.id": (v29/*: any*/),
        "node.subIssues.nodes.repository.owner.login": (v26/*: any*/),
        "node.subIssues.nodes.state": (v41/*: any*/),
        "node.subIssues.nodes.stateReason": (v42/*: any*/),
        "node.subIssues.nodes.subIssuesSummary": (v43/*: any*/),
        "node.subIssues.nodes.subIssuesSummary.completed": (v31/*: any*/),
        "node.subIssues.nodes.subIssuesSummary.total": (v31/*: any*/),
        "node.subIssues.nodes.title": (v26/*: any*/),
        "node.subIssues.nodes.titleHTML": (v26/*: any*/),
        "node.subIssues.nodes.url": (v35/*: any*/),
        "node.subIssuesConnection": (v46/*: any*/),
        "node.subIssuesConnection.totalCount": (v31/*: any*/),
        "node.taskListSummary": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TaskListSummary"
        },
        "node.taskListSummary.completeCount": (v31/*: any*/),
        "node.taskListSummary.itemCount": (v31/*: any*/),
        "node.tasklistBlocksCompletion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TrackedIssueCompletion"
        },
        "node.tasklistBlocksCompletion.completed": (v31/*: any*/),
        "node.tasklistBlocksCompletion.total": (v31/*: any*/),
        "node.threadSubscriptionChannel": (v45/*: any*/),
        "node.title": (v26/*: any*/),
        "node.trackedInIssues": (v46/*: any*/),
        "node.trackedInIssues.nodes": (v47/*: any*/),
        "node.trackedInIssues.nodes.id": (v29/*: any*/),
        "node.trackedInIssues.nodes.number": (v31/*: any*/),
        "node.trackedInIssues.nodes.stateReason": (v42/*: any*/),
        "node.trackedInIssues.nodes.url": (v35/*: any*/),
        "node.trackedInIssues.totalCount": (v31/*: any*/),
        "node.viewerCanBlockFromOrg": (v30/*: any*/),
        "node.viewerCanClose": (v30/*: any*/),
        "node.viewerCanConvertToDiscussion": (v48/*: any*/),
        "node.viewerCanDelete": (v30/*: any*/),
        "node.viewerCanLinkBranches": (v30/*: any*/),
        "node.viewerCanLock": (v48/*: any*/),
        "node.viewerCanReadUserContentEdits": (v30/*: any*/),
        "node.viewerCanReopen": (v30/*: any*/),
        "node.viewerCanReport": (v30/*: any*/),
        "node.viewerCanReportToMaintainer": (v30/*: any*/),
        "node.viewerCanTransfer": (v30/*: any*/),
        "node.viewerCanType": (v48/*: any*/),
        "node.viewerCanUnblockFromOrg": (v30/*: any*/),
        "node.viewerCanUpdateMetadata": (v48/*: any*/),
        "node.viewerCustomSubscriptionEvents": {
          "enumValues": [
            "CLOSED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": true,
          "type": "ThreadSubscriptionEvent"
        },
        "node.viewerThreadSubscriptionFormAction": {
          "enumValues": [
            "NONE",
            "SUBSCRIBE",
            "UNSUBSCRIBE"
          ],
          "nullable": true,
          "plural": false,
          "type": "ThreadSubscriptionFormAction"
        }
      }
    },
    "name": "IssueViewerTestComponentSecondaryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a9790308bcaf25c201e13284602be20e";

export default node;
