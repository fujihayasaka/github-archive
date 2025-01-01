/**
 * @generated SignedSource<<413038ea4fbe8776a18e042142017282>>
 * @relayHash a33a100136a9961c3acb967b2047646b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a33a100136a9961c3acb967b2047646b

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
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v20 = [
  (v19/*: any*/)
],
v21 = {
  "alias": null,
  "args": null,
  "concreteType": "PullRequestConnection",
  "kind": "LinkedField",
  "name": "associatedPullRequests",
  "plural": false,
  "selections": (v20/*: any*/),
  "storageKey": null
},
v22 = [
  (v3/*: any*/)
],
v23 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v24 = {
  "kind": "Literal",
  "name": "includeClosedPrs",
  "value": true
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isDraft",
  "storageKey": null
},
v26 = {
  "kind": "Literal",
  "name": "first",
  "value": 3
},
v27 = {
  "kind": "Literal",
  "name": "ranked",
  "value": true
},
v28 = [
  (v26/*: any*/),
  (v27/*: any*/)
],
v29 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v8/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v30 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v3/*: any*/),
      (v11/*: any*/),
      (v12/*: any*/),
      (v13/*: any*/),
      (v4/*: any*/),
      (v29/*: any*/),
      (v9/*: any*/),
      (v10/*: any*/)
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
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "hasNextPage",
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v31 = [
  (v23/*: any*/)
],
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v33 = {
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
v34 = {
  "kind": "InlineFragment",
  "selections": [
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
v35 = {
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
v36 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v39 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v40 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v41 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v42 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v43 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v44 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v45 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v46 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v47 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v48 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v49 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v50 = {
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
v51 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v52 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v53 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v54 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v55 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "SubIssuesSummary"
},
v56 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v57 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v58 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v59 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v60 = {
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
                          (v18/*: any*/),
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
                                  (v18/*: any*/),
                                  (v21/*: any*/),
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "Repository",
                                    "kind": "LinkedField",
                                    "name": "repository",
                                    "plural": false,
                                    "selections": (v22/*: any*/),
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          (v21/*: any*/)
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
                  (v23/*: any*/),
                  (v24/*: any*/)
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
                      (v25/*: any*/),
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
                  (v23/*: any*/),
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
                      (v25/*: any*/),
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
                "alias": "topBlockedBy",
                "args": (v28/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
                "plural": false,
                "selections": (v30/*: any*/),
                "storageKey": "blockedBy(first:3,ranked:true)"
              },
              {
                "alias": "topBlocking",
                "args": (v28/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blocking",
                "plural": false,
                "selections": (v30/*: any*/),
                "storageKey": "blocking(first:3,ranked:true)"
              },
              {
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
                      (v3/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v2/*: any*/),
                          (v6/*: any*/),
                          (v5/*: any*/),
                          (v32/*: any*/),
                          (v33/*: any*/),
                          (v34/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      }
                    ],
                    "storageKey": null
                  },
                  (v19/*: any*/)
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
              (v13/*: any*/),
              {
                "alias": null,
                "args": [
                  (v26/*: any*/)
                ],
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "duplicateIssues",
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
                      (v4/*: any*/),
                      (v11/*: any*/),
                      (v9/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "stateReason",
                        "storageKey": null
                      },
                      (v13/*: any*/),
                      (v29/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "duplicateIssues(first:3)"
              },
              {
                "alias": null,
                "args": (v31/*: any*/),
                "concreteType": "AssigneeConnection",
                "kind": "LinkedField",
                "name": "suggestedActors",
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
                      (v2/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v3/*: any*/),
                          (v6/*: any*/),
                          (v5/*: any*/),
                          (v32/*: any*/),
                          (v33/*: any*/),
                          (v34/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": (v22/*: any*/),
                        "type": "Node",
                        "abstractKey": "__isNode"
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "suggestedActors(first:10)"
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
                      (v4/*: any*/),
                      (v13/*: any*/),
                      (v10/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v19/*: any*/)
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
                        "args": (v31/*: any*/),
                        "concreteType": "UserConnection",
                        "kind": "LinkedField",
                        "name": "assignees",
                        "plural": false,
                        "selections": [
                          (v19/*: any*/),
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
                      (v35/*: any*/),
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
                          (v24/*: any*/)
                        ],
                        "concreteType": "PullRequestConnection",
                        "kind": "LinkedField",
                        "name": "closedByPullRequestsReferences",
                        "plural": false,
                        "selections": (v20/*: any*/),
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
                "selections": (v20/*: any*/),
                "storageKey": null
              },
              (v9/*: any*/),
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 1
                  },
                  (v27/*: any*/)
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
                      (v11/*: any*/),
                      (v4/*: any*/),
                      (v13/*: any*/),
                      (v35/*: any*/),
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "blockedBy(first:1,ranked:true)"
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
    "id": "a33a100136a9961c3acb967b2047646b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isComment": (v36/*: any*/),
        "node.__typename": (v36/*: any*/),
        "node.blockedBy": (v37/*: any*/),
        "node.blockedBy.nodes": (v38/*: any*/),
        "node.blockedBy.nodes.id": (v39/*: any*/),
        "node.blockedBy.nodes.number": (v40/*: any*/),
        "node.blockedBy.nodes.repository": (v41/*: any*/),
        "node.blockedBy.nodes.repository.id": (v39/*: any*/),
        "node.blockedBy.nodes.repository.name": (v36/*: any*/),
        "node.blockedBy.nodes.repository.owner": (v42/*: any*/),
        "node.blockedBy.nodes.repository.owner.__typename": (v36/*: any*/),
        "node.blockedBy.nodes.repository.owner.id": (v39/*: any*/),
        "node.blockedBy.nodes.repository.owner.login": (v36/*: any*/),
        "node.blockedBy.nodes.title": (v36/*: any*/),
        "node.blockedBy.nodes.url": (v43/*: any*/),
        "node.closedByPullRequestsReferences": (v44/*: any*/),
        "node.closedByPullRequestsReferences.nodes": (v45/*: any*/),
        "node.closedByPullRequestsReferences.nodes.__typename": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.closedByPullRequestsReferences.nodes.id": (v39/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isDraft": (v46/*: any*/),
        "node.closedByPullRequestsReferences.nodes.isInMergeQueue": (v46/*: any*/),
        "node.closedByPullRequestsReferences.nodes.number": (v40/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository": (v41/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.id": (v39/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.name": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner": (v42/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.id": (v39/*: any*/),
        "node.closedByPullRequestsReferences.nodes.repository.owner.login": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.state": (v47/*: any*/),
        "node.closedByPullRequestsReferences.nodes.title": (v36/*: any*/),
        "node.closedByPullRequestsReferences.nodes.url": (v43/*: any*/),
        "node.databaseId": (v48/*: any*/),
        "node.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "node.discussion.id": (v39/*: any*/),
        "node.discussion.url": (v43/*: any*/),
        "node.duplicateIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueConnection"
        },
        "node.duplicateIssues.nodes": (v38/*: any*/),
        "node.duplicateIssues.nodes.id": (v39/*: any*/),
        "node.duplicateIssues.nodes.number": (v40/*: any*/),
        "node.duplicateIssues.nodes.repository": (v41/*: any*/),
        "node.duplicateIssues.nodes.repository.id": (v39/*: any*/),
        "node.duplicateIssues.nodes.repository.nameWithOwner": (v36/*: any*/),
        "node.duplicateIssues.nodes.state": (v49/*: any*/),
        "node.duplicateIssues.nodes.stateReason": (v50/*: any*/),
        "node.duplicateIssues.nodes.title": (v36/*: any*/),
        "node.duplicateIssues.nodes.url": (v43/*: any*/),
        "node.id": (v39/*: any*/),
        "node.isTransferInProgress": (v46/*: any*/),
        "node.issueDependenciesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueDependenciesSummary"
        },
        "node.issueDependenciesSummary.blockedBy": (v40/*: any*/),
        "node.issueDependenciesSummary.blocking": (v40/*: any*/),
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
        "node.lastUserContentEdit.editor.__typename": (v36/*: any*/),
        "node.lastUserContentEdit.editor.id": (v39/*: any*/),
        "node.lastUserContentEdit.editor.login": (v36/*: any*/),
        "node.lastUserContentEdit.editor.url": (v43/*: any*/),
        "node.lastUserContentEdit.id": (v39/*: any*/),
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
        "node.linkedBranches.nodes.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref": (v51/*: any*/),
        "node.linkedBranches.nodes.ref.__typename": (v36/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests": (v52/*: any*/),
        "node.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v40/*: any*/),
        "node.linkedBranches.nodes.ref.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.name": (v36/*: any*/),
        "node.linkedBranches.nodes.ref.repository": (v41/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef": (v51/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v52/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v40/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v36/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v41/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v53/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v36/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v54/*: any*/),
        "node.linkedBranches.nodes.ref.repository.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.repository.nameWithOwner": (v36/*: any*/),
        "node.linkedBranches.nodes.ref.target": (v53/*: any*/),
        "node.linkedBranches.nodes.ref.target.__typename": (v36/*: any*/),
        "node.linkedBranches.nodes.ref.target.id": (v39/*: any*/),
        "node.linkedBranches.nodes.ref.target.oid": (v54/*: any*/),
        "node.linkedPullRequests": (v44/*: any*/),
        "node.linkedPullRequests.nodes": (v45/*: any*/),
        "node.linkedPullRequests.nodes.id": (v39/*: any*/),
        "node.linkedPullRequests.nodes.isDraft": (v46/*: any*/),
        "node.linkedPullRequests.nodes.number": (v40/*: any*/),
        "node.linkedPullRequests.nodes.repository": (v41/*: any*/),
        "node.linkedPullRequests.nodes.repository.id": (v39/*: any*/),
        "node.linkedPullRequests.nodes.repository.name": (v36/*: any*/),
        "node.linkedPullRequests.nodes.repository.nameWithOwner": (v36/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner": (v42/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.__typename": (v36/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.id": (v39/*: any*/),
        "node.linkedPullRequests.nodes.repository.owner.login": (v36/*: any*/),
        "node.linkedPullRequests.nodes.state": (v47/*: any*/),
        "node.linkedPullRequests.nodes.url": (v43/*: any*/),
        "node.number": (v40/*: any*/),
        "node.parent": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "node.parent.id": (v39/*: any*/),
        "node.parent.number": (v40/*: any*/),
        "node.parent.repository": (v41/*: any*/),
        "node.parent.repository.id": (v39/*: any*/),
        "node.parent.repository.name": (v36/*: any*/),
        "node.parent.repository.nameWithOwner": (v36/*: any*/),
        "node.parent.repository.owner": (v42/*: any*/),
        "node.parent.repository.owner.__typename": (v36/*: any*/),
        "node.parent.repository.owner.id": (v39/*: any*/),
        "node.parent.repository.owner.login": (v36/*: any*/),
        "node.parent.state": (v49/*: any*/),
        "node.parent.stateReason": (v50/*: any*/),
        "node.parent.subIssuesSummary": (v55/*: any*/),
        "node.parent.subIssuesSummary.completed": (v40/*: any*/),
        "node.parent.subIssuesSummary.total": (v40/*: any*/),
        "node.parent.title": (v36/*: any*/),
        "node.parent.titleHTML": (v36/*: any*/),
        "node.parent.url": (v43/*: any*/),
        "node.participants": (v56/*: any*/),
        "node.participants.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "node.participants.nodes.__isActor": (v36/*: any*/),
        "node.participants.nodes.__typename": (v36/*: any*/),
        "node.participants.nodes.avatarUrl": (v43/*: any*/),
        "node.participants.nodes.id": (v39/*: any*/),
        "node.participants.nodes.isCopilot": (v46/*: any*/),
        "node.participants.nodes.login": (v36/*: any*/),
        "node.participants.nodes.name": (v57/*: any*/),
        "node.participants.nodes.profileResourcePath": (v58/*: any*/),
        "node.participants.totalCount": (v40/*: any*/),
        "node.repository": (v41/*: any*/),
        "node.repository.databaseId": (v48/*: any*/),
        "node.repository.id": (v39/*: any*/),
        "node.repository.isArchived": (v46/*: any*/),
        "node.repository.name": (v36/*: any*/),
        "node.repository.nameWithOwner": (v36/*: any*/),
        "node.repository.owner": (v42/*: any*/),
        "node.repository.owner.__typename": (v36/*: any*/),
        "node.repository.owner.id": (v39/*: any*/),
        "node.repository.owner.login": (v36/*: any*/),
        "node.repository.slashCommandsEnabled": (v46/*: any*/),
        "node.repository.viewerCanPinIssues": (v46/*: any*/),
        "node.showSpammyBadge": (v46/*: any*/),
        "node.state": (v49/*: any*/),
        "node.subIssues": (v37/*: any*/),
        "node.subIssues.nodes": (v38/*: any*/),
        "node.subIssues.nodes.assignees": (v56/*: any*/),
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
        "node.subIssues.nodes.assignees.edges.node.avatarUrl": (v43/*: any*/),
        "node.subIssues.nodes.assignees.edges.node.id": (v39/*: any*/),
        "node.subIssues.nodes.assignees.edges.node.login": (v36/*: any*/),
        "node.subIssues.nodes.assignees.totalCount": (v40/*: any*/),
        "node.subIssues.nodes.closed": (v46/*: any*/),
        "node.subIssues.nodes.closedByPullRequestsReferences": (v44/*: any*/),
        "node.subIssues.nodes.closedByPullRequestsReferences.totalCount": (v40/*: any*/),
        "node.subIssues.nodes.databaseId": (v48/*: any*/),
        "node.subIssues.nodes.id": (v39/*: any*/),
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
        "node.subIssues.nodes.issueType.id": (v39/*: any*/),
        "node.subIssues.nodes.issueType.name": (v36/*: any*/),
        "node.subIssues.nodes.number": (v40/*: any*/),
        "node.subIssues.nodes.repository": (v41/*: any*/),
        "node.subIssues.nodes.repository.id": (v39/*: any*/),
        "node.subIssues.nodes.repository.name": (v36/*: any*/),
        "node.subIssues.nodes.repository.owner": (v42/*: any*/),
        "node.subIssues.nodes.repository.owner.__typename": (v36/*: any*/),
        "node.subIssues.nodes.repository.owner.id": (v39/*: any*/),
        "node.subIssues.nodes.repository.owner.login": (v36/*: any*/),
        "node.subIssues.nodes.state": (v49/*: any*/),
        "node.subIssues.nodes.stateReason": (v50/*: any*/),
        "node.subIssues.nodes.subIssuesSummary": (v55/*: any*/),
        "node.subIssues.nodes.subIssuesSummary.completed": (v40/*: any*/),
        "node.subIssues.nodes.subIssuesSummary.total": (v40/*: any*/),
        "node.subIssues.nodes.title": (v36/*: any*/),
        "node.subIssues.nodes.titleHTML": (v36/*: any*/),
        "node.subIssues.nodes.url": (v43/*: any*/),
        "node.subIssuesConnection": (v37/*: any*/),
        "node.subIssuesConnection.totalCount": (v40/*: any*/),
        "node.suggestedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "node.suggestedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "node.suggestedActors.nodes.__isActor": (v36/*: any*/),
        "node.suggestedActors.nodes.__isNode": (v36/*: any*/),
        "node.suggestedActors.nodes.__typename": (v36/*: any*/),
        "node.suggestedActors.nodes.avatarUrl": (v43/*: any*/),
        "node.suggestedActors.nodes.id": (v39/*: any*/),
        "node.suggestedActors.nodes.isCopilot": (v46/*: any*/),
        "node.suggestedActors.nodes.login": (v36/*: any*/),
        "node.suggestedActors.nodes.name": (v57/*: any*/),
        "node.suggestedActors.nodes.profileResourcePath": (v58/*: any*/),
        "node.taskListSummary": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TaskListSummary"
        },
        "node.taskListSummary.completeCount": (v40/*: any*/),
        "node.taskListSummary.itemCount": (v40/*: any*/),
        "node.tasklistBlocksCompletion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TrackedIssueCompletion"
        },
        "node.tasklistBlocksCompletion.completed": (v40/*: any*/),
        "node.tasklistBlocksCompletion.total": (v40/*: any*/),
        "node.threadSubscriptionChannel": (v57/*: any*/),
        "node.title": (v36/*: any*/),
        "node.topBlockedBy": (v37/*: any*/),
        "node.topBlockedBy.nodes": (v38/*: any*/),
        "node.topBlockedBy.nodes.id": (v39/*: any*/),
        "node.topBlockedBy.nodes.number": (v40/*: any*/),
        "node.topBlockedBy.nodes.repository": (v41/*: any*/),
        "node.topBlockedBy.nodes.repository.id": (v39/*: any*/),
        "node.topBlockedBy.nodes.repository.nameWithOwner": (v36/*: any*/),
        "node.topBlockedBy.nodes.state": (v49/*: any*/),
        "node.topBlockedBy.nodes.stateReason": (v50/*: any*/),
        "node.topBlockedBy.nodes.title": (v36/*: any*/),
        "node.topBlockedBy.nodes.titleHTML": (v36/*: any*/),
        "node.topBlockedBy.nodes.url": (v43/*: any*/),
        "node.topBlockedBy.pageInfo": (v59/*: any*/),
        "node.topBlockedBy.pageInfo.hasNextPage": (v46/*: any*/),
        "node.topBlocking": (v37/*: any*/),
        "node.topBlocking.nodes": (v38/*: any*/),
        "node.topBlocking.nodes.id": (v39/*: any*/),
        "node.topBlocking.nodes.number": (v40/*: any*/),
        "node.topBlocking.nodes.repository": (v41/*: any*/),
        "node.topBlocking.nodes.repository.id": (v39/*: any*/),
        "node.topBlocking.nodes.repository.nameWithOwner": (v36/*: any*/),
        "node.topBlocking.nodes.state": (v49/*: any*/),
        "node.topBlocking.nodes.stateReason": (v50/*: any*/),
        "node.topBlocking.nodes.title": (v36/*: any*/),
        "node.topBlocking.nodes.titleHTML": (v36/*: any*/),
        "node.topBlocking.nodes.url": (v43/*: any*/),
        "node.topBlocking.pageInfo": (v59/*: any*/),
        "node.topBlocking.pageInfo.hasNextPage": (v46/*: any*/),
        "node.trackedInIssues": (v37/*: any*/),
        "node.trackedInIssues.nodes": (v38/*: any*/),
        "node.trackedInIssues.nodes.id": (v39/*: any*/),
        "node.trackedInIssues.nodes.number": (v40/*: any*/),
        "node.trackedInIssues.nodes.stateReason": (v50/*: any*/),
        "node.trackedInIssues.nodes.url": (v43/*: any*/),
        "node.trackedInIssues.totalCount": (v40/*: any*/),
        "node.url": (v43/*: any*/),
        "node.viewerCanBlockFromOrg": (v46/*: any*/),
        "node.viewerCanClose": (v46/*: any*/),
        "node.viewerCanConvertToDiscussion": (v60/*: any*/),
        "node.viewerCanDelete": (v46/*: any*/),
        "node.viewerCanLinkBranches": (v46/*: any*/),
        "node.viewerCanLock": (v60/*: any*/),
        "node.viewerCanReadUserContentEdits": (v46/*: any*/),
        "node.viewerCanReopen": (v46/*: any*/),
        "node.viewerCanReport": (v46/*: any*/),
        "node.viewerCanReportToMaintainer": (v46/*: any*/),
        "node.viewerCanTransfer": (v46/*: any*/),
        "node.viewerCanType": (v60/*: any*/),
        "node.viewerCanUnblockFromOrg": (v46/*: any*/),
        "node.viewerCanUpdateMetadata": (v60/*: any*/),
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

(node as any).hash = "734f4d976f9199188bffb67af591c5fb";

export default node;
