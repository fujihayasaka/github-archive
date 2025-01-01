/**
 * @generated SignedSource<<7f6fe289f3f2b35bdf704909d6842db3>>
 * @relayHash 79901e09c96ba7bca55d27ee5ffe4993
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 79901e09c96ba7bca55d27ee5ffe4993

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueViewerTestComponentSecondaryTestQuery$variables = Record<PropertyKey, never>;
export type IssueViewerTestComponentSecondaryTestQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryIssueData">;
    } | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerSecondaryViewQueryRepoData">;
  } | null | undefined;
};
export type IssueViewerTestComponentSecondaryTestQuery = {
  response: IssueViewerTestComponentSecondaryTestQuery$data;
  variables: IssueViewerTestComponentSecondaryTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = [
  {
    "kind": "Literal",
    "name": "number",
    "value": 10
  }
],
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
  "name": "number",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
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
    (v5/*: any*/),
    (v6/*: any*/),
    (v2/*: any*/)
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
    (v2/*: any*/),
    (v5/*: any*/)
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
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v27 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v28 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v31 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v34 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v36 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v39 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v40 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v41 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v42 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v43 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v44 = {
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
v45 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "SubIssuesSummary"
},
v46 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v47 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v48 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v49 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v50 = {
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
    "name": "IssueViewerTestComponentSecondaryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "IssueViewerSecondaryViewQueryRepoData"
          },
          {
            "alias": null,
            "args": (v1/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueViewerSecondaryIssueData"
              }
            ],
            "storageKey": "issue(number:10)"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueViewerTestComponentSecondaryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
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
          {
            "alias": null,
            "args": (v1/*: any*/),
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
                  (v2/*: any*/),
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "repository",
                    "plural": false,
                    "selections": [
                      (v4/*: any*/),
                      (v7/*: any*/),
                      (v2/*: any*/),
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
                  (v2/*: any*/)
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
                  (v2/*: any*/),
                  (v17/*: any*/),
                  (v4/*: any*/),
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
                                  (v2/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "slug",
                                    "storageKey": null
                                  },
                                  (v4/*: any*/)
                                ],
                                "storageKey": null
                              },
                              (v2/*: any*/)
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
              (v2/*: any*/),
              (v11/*: any*/),
              (v3/*: any*/),
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
                      (v2/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Ref",
                        "kind": "LinkedField",
                        "name": "ref",
                        "plural": false,
                        "selections": [
                          (v4/*: any*/),
                          (v2/*: any*/),
                          (v5/*: any*/),
                          (v19/*: any*/),
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
                                "concreteType": "Ref",
                                "kind": "LinkedField",
                                "name": "defaultBranchRef",
                                "plural": false,
                                "selections": [
                                  (v4/*: any*/),
                                  (v2/*: any*/),
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
                                      (v2/*: any*/)
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
                      (v2/*: any*/),
                      (v5/*: any*/),
                      (v13/*: any*/),
                      (v3/*: any*/),
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
                          (v2/*: any*/),
                          (v4/*: any*/),
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
                              (v5/*: any*/),
                              (v2/*: any*/)
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
                          (v2/*: any*/),
                          (v4/*: any*/),
                          (v7/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v9/*: any*/),
                      (v24/*: any*/),
                      (v13/*: any*/),
                      (v3/*: any*/),
                      (v2/*: any*/)
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
                      (v2/*: any*/),
                      (v6/*: any*/),
                      (v4/*: any*/),
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
                      (v3/*: any*/),
                      (v13/*: any*/),
                      (v10/*: any*/),
                      (v2/*: any*/)
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
                      (v2/*: any*/),
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
                                  (v2/*: any*/),
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
                          (v4/*: any*/),
                          (v7/*: any*/),
                          (v2/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v17/*: any*/),
                      (v3/*: any*/),
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
                          (v2/*: any*/),
                          (v4/*: any*/),
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
                          (v5/*: any*/),
                          (v13/*: any*/),
                          (v6/*: any*/),
                          (v2/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v2/*: any*/)
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
            "storageKey": "issue(number:10)"
          },
          (v2/*: any*/)
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "79901e09c96ba7bca55d27ee5ffe4993",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.codeOfConductFileUrl": (v26/*: any*/),
        "repository.contributingFileUrl": (v26/*: any*/),
        "repository.id": (v27/*: any*/),
        "repository.issue": (v28/*: any*/),
        "repository.issue.__isComment": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences": (v30/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes": (v31/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.__typename": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "repository.issue.closedByPullRequestsReferences.nodes.id": (v27/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.isDraft": (v32/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.isInMergeQueue": (v32/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.number": (v33/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository": (v34/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.id": (v27/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.name": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner": (v35/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.id": (v27/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.login": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.state": (v36/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.title": (v29/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.url": (v37/*: any*/),
        "repository.issue.databaseId": (v38/*: any*/),
        "repository.issue.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "repository.issue.discussion.id": (v27/*: any*/),
        "repository.issue.discussion.url": (v37/*: any*/),
        "repository.issue.id": (v27/*: any*/),
        "repository.issue.isTransferInProgress": (v32/*: any*/),
        "repository.issue.lastEditedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "repository.issue.lastUserContentEdit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "UserContentEdit"
        },
        "repository.issue.lastUserContentEdit.editor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "repository.issue.lastUserContentEdit.editor.__typename": (v29/*: any*/),
        "repository.issue.lastUserContentEdit.editor.id": (v27/*: any*/),
        "repository.issue.lastUserContentEdit.editor.login": (v29/*: any*/),
        "repository.issue.lastUserContentEdit.editor.url": (v37/*: any*/),
        "repository.issue.lastUserContentEdit.id": (v27/*: any*/),
        "repository.issue.linkedBranches": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "LinkedBranchConnection"
        },
        "repository.issue.linkedBranches.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LinkedBranch"
        },
        "repository.issue.linkedBranches.nodes.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.__typename": (v29/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.associatedPullRequests": (v40/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v33/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.name": (v29/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository": (v34/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v40/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v33/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v29/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v34/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v41/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v29/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v42/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.nameWithOwner": (v29/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target": (v41/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.__typename": (v29/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.id": (v27/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.oid": (v42/*: any*/),
        "repository.issue.linkedPullRequests": (v30/*: any*/),
        "repository.issue.linkedPullRequests.nodes": (v31/*: any*/),
        "repository.issue.linkedPullRequests.nodes.id": (v27/*: any*/),
        "repository.issue.linkedPullRequests.nodes.isDraft": (v32/*: any*/),
        "repository.issue.linkedPullRequests.nodes.number": (v33/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository": (v34/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.id": (v27/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.name": (v29/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.nameWithOwner": (v29/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner": (v35/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.__typename": (v29/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.id": (v27/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.login": (v29/*: any*/),
        "repository.issue.linkedPullRequests.nodes.state": (v36/*: any*/),
        "repository.issue.linkedPullRequests.nodes.url": (v37/*: any*/),
        "repository.issue.number": (v33/*: any*/),
        "repository.issue.parent": (v28/*: any*/),
        "repository.issue.parent.id": (v27/*: any*/),
        "repository.issue.parent.number": (v33/*: any*/),
        "repository.issue.parent.repository": (v34/*: any*/),
        "repository.issue.parent.repository.id": (v27/*: any*/),
        "repository.issue.parent.repository.name": (v29/*: any*/),
        "repository.issue.parent.repository.nameWithOwner": (v29/*: any*/),
        "repository.issue.parent.repository.owner": (v35/*: any*/),
        "repository.issue.parent.repository.owner.__typename": (v29/*: any*/),
        "repository.issue.parent.repository.owner.id": (v27/*: any*/),
        "repository.issue.parent.repository.owner.login": (v29/*: any*/),
        "repository.issue.parent.state": (v43/*: any*/),
        "repository.issue.parent.stateReason": (v44/*: any*/),
        "repository.issue.parent.subIssuesSummary": (v45/*: any*/),
        "repository.issue.parent.subIssuesSummary.completed": (v33/*: any*/),
        "repository.issue.parent.subIssuesSummary.total": (v33/*: any*/),
        "repository.issue.parent.title": (v29/*: any*/),
        "repository.issue.parent.titleHTML": (v29/*: any*/),
        "repository.issue.parent.url": (v37/*: any*/),
        "repository.issue.participants": (v46/*: any*/),
        "repository.issue.participants.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "repository.issue.participants.nodes.avatarUrl": (v37/*: any*/),
        "repository.issue.participants.nodes.id": (v27/*: any*/),
        "repository.issue.participants.nodes.login": (v29/*: any*/),
        "repository.issue.participants.nodes.name": (v47/*: any*/),
        "repository.issue.participants.totalCount": (v33/*: any*/),
        "repository.issue.repository": (v34/*: any*/),
        "repository.issue.repository.databaseId": (v38/*: any*/),
        "repository.issue.repository.id": (v27/*: any*/),
        "repository.issue.repository.installedAppInstallations": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "InstalledAppInstallationsConnection"
        },
        "repository.issue.repository.installedAppInstallations.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IntegrationInstallationEdge"
        },
        "repository.issue.repository.installedAppInstallations.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IntegrationInstallation"
        },
        "repository.issue.repository.installedAppInstallations.edges.node.app": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "App"
        },
        "repository.issue.repository.installedAppInstallations.edges.node.app.id": (v27/*: any*/),
        "repository.issue.repository.installedAppInstallations.edges.node.app.name": (v29/*: any*/),
        "repository.issue.repository.installedAppInstallations.edges.node.app.slug": (v29/*: any*/),
        "repository.issue.repository.installedAppInstallations.edges.node.id": (v27/*: any*/),
        "repository.issue.repository.isArchived": (v32/*: any*/),
        "repository.issue.repository.name": (v29/*: any*/),
        "repository.issue.repository.nameWithOwner": (v29/*: any*/),
        "repository.issue.repository.owner": (v35/*: any*/),
        "repository.issue.repository.owner.__typename": (v29/*: any*/),
        "repository.issue.repository.owner.id": (v27/*: any*/),
        "repository.issue.repository.owner.login": (v29/*: any*/),
        "repository.issue.repository.slashCommandsEnabled": (v32/*: any*/),
        "repository.issue.repository.viewerCanPinIssues": (v32/*: any*/),
        "repository.issue.showSpammyBadge": (v32/*: any*/),
        "repository.issue.subIssues": (v48/*: any*/),
        "repository.issue.subIssues.nodes": (v49/*: any*/),
        "repository.issue.subIssues.nodes.assignees": (v46/*: any*/),
        "repository.issue.subIssues.nodes.assignees.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "UserEdge"
        },
        "repository.issue.subIssues.nodes.assignees.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "User"
        },
        "repository.issue.subIssues.nodes.assignees.edges.node.avatarUrl": (v37/*: any*/),
        "repository.issue.subIssues.nodes.assignees.edges.node.id": (v27/*: any*/),
        "repository.issue.subIssues.nodes.assignees.edges.node.login": (v29/*: any*/),
        "repository.issue.subIssues.nodes.assignees.totalCount": (v33/*: any*/),
        "repository.issue.subIssues.nodes.closed": (v32/*: any*/),
        "repository.issue.subIssues.nodes.closedByPullRequestsReferences": (v30/*: any*/),
        "repository.issue.subIssues.nodes.closedByPullRequestsReferences.totalCount": (v33/*: any*/),
        "repository.issue.subIssues.nodes.databaseId": (v38/*: any*/),
        "repository.issue.subIssues.nodes.id": (v27/*: any*/),
        "repository.issue.subIssues.nodes.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "repository.issue.subIssues.nodes.issueType.color": {
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
        "repository.issue.subIssues.nodes.issueType.id": (v27/*: any*/),
        "repository.issue.subIssues.nodes.issueType.name": (v29/*: any*/),
        "repository.issue.subIssues.nodes.number": (v33/*: any*/),
        "repository.issue.subIssues.nodes.repository": (v34/*: any*/),
        "repository.issue.subIssues.nodes.repository.id": (v27/*: any*/),
        "repository.issue.subIssues.nodes.repository.name": (v29/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner": (v35/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner.__typename": (v29/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner.id": (v27/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner.login": (v29/*: any*/),
        "repository.issue.subIssues.nodes.state": (v43/*: any*/),
        "repository.issue.subIssues.nodes.stateReason": (v44/*: any*/),
        "repository.issue.subIssues.nodes.subIssuesSummary": (v45/*: any*/),
        "repository.issue.subIssues.nodes.subIssuesSummary.completed": (v33/*: any*/),
        "repository.issue.subIssues.nodes.subIssuesSummary.total": (v33/*: any*/),
        "repository.issue.subIssues.nodes.title": (v29/*: any*/),
        "repository.issue.subIssues.nodes.titleHTML": (v29/*: any*/),
        "repository.issue.subIssues.nodes.url": (v37/*: any*/),
        "repository.issue.subIssuesConnection": (v48/*: any*/),
        "repository.issue.subIssuesConnection.totalCount": (v33/*: any*/),
        "repository.issue.taskListSummary": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TaskListSummary"
        },
        "repository.issue.taskListSummary.completeCount": (v33/*: any*/),
        "repository.issue.taskListSummary.itemCount": (v33/*: any*/),
        "repository.issue.tasklistBlocksCompletion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TrackedIssueCompletion"
        },
        "repository.issue.tasklistBlocksCompletion.completed": (v33/*: any*/),
        "repository.issue.tasklistBlocksCompletion.total": (v33/*: any*/),
        "repository.issue.threadSubscriptionChannel": (v47/*: any*/),
        "repository.issue.title": (v29/*: any*/),
        "repository.issue.trackedInIssues": (v48/*: any*/),
        "repository.issue.trackedInIssues.nodes": (v49/*: any*/),
        "repository.issue.trackedInIssues.nodes.id": (v27/*: any*/),
        "repository.issue.trackedInIssues.nodes.number": (v33/*: any*/),
        "repository.issue.trackedInIssues.nodes.stateReason": (v44/*: any*/),
        "repository.issue.trackedInIssues.nodes.url": (v37/*: any*/),
        "repository.issue.trackedInIssues.totalCount": (v33/*: any*/),
        "repository.issue.viewerCanBlockFromOrg": (v32/*: any*/),
        "repository.issue.viewerCanClose": (v32/*: any*/),
        "repository.issue.viewerCanConvertToDiscussion": (v50/*: any*/),
        "repository.issue.viewerCanDelete": (v32/*: any*/),
        "repository.issue.viewerCanLinkBranches": (v32/*: any*/),
        "repository.issue.viewerCanLock": (v50/*: any*/),
        "repository.issue.viewerCanReadUserContentEdits": (v32/*: any*/),
        "repository.issue.viewerCanReopen": (v32/*: any*/),
        "repository.issue.viewerCanReport": (v32/*: any*/),
        "repository.issue.viewerCanReportToMaintainer": (v32/*: any*/),
        "repository.issue.viewerCanTransfer": (v32/*: any*/),
        "repository.issue.viewerCanType": (v50/*: any*/),
        "repository.issue.viewerCanUnblockFromOrg": (v32/*: any*/),
        "repository.issue.viewerCanUpdateMetadata": (v50/*: any*/),
        "repository.issue.viewerCustomSubscriptionEvents": {
          "enumValues": [
            "CLOSED",
            "REOPENED"
          ],
          "nullable": true,
          "plural": true,
          "type": "ThreadSubscriptionEvent"
        },
        "repository.issue.viewerThreadSubscriptionFormAction": {
          "enumValues": [
            "NONE",
            "SUBSCRIBE",
            "UNSUBSCRIBE"
          ],
          "nullable": true,
          "plural": false,
          "type": "ThreadSubscriptionFormAction"
        },
        "repository.securityPolicyUrl": (v26/*: any*/)
      }
    },
    "name": "IssueViewerTestComponentSecondaryTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "75cc03ecece2caf4d0efc4e897b8aac7";

export default node;
