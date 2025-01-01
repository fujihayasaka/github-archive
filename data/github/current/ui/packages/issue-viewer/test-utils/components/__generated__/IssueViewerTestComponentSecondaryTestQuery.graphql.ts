/**
 * @generated SignedSource<<865021cc67e4ababad169adf501f5e76>>
 * @relayHash 9d1f3804e9e454cb0a0199b36b10a695
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9d1f3804e9e454cb0a0199b36b10a695

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
  (v2/*: any*/)
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
    (v2/*: any*/)
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
      (v2/*: any*/),
      (v11/*: any*/),
      (v12/*: any*/),
      (v13/*: any*/),
      (v3/*: any*/),
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
    (v4/*: any*/),
    (v7/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v36 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v39 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v40 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v41 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "Issue"
},
v42 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v43 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v44 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v45 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v46 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestConnection"
},
v47 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequest"
},
v48 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v49 = {
  "enumValues": [
    "CLOSED",
    "MERGED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "PullRequestState"
},
v50 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v51 = {
  "enumValues": [
    "CLOSED",
    "OPEN"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueState"
},
v52 = {
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
v53 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Ref"
},
v54 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestConnection"
},
v55 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "GitObject"
},
v56 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "GitObjectID"
},
v57 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "SubIssuesSummary"
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v60 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v61 = {
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
            "args": null,
            "kind": "ScalarField",
            "name": "supportFileUrl",
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
              (v2/*: any*/),
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
                  }
                ],
                "storageKey": null
              },
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
                          (v18/*: any*/),
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
                      (v2/*: any*/),
                      (v5/*: any*/),
                      (v13/*: any*/),
                      (v3/*: any*/),
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
                          (v2/*: any*/),
                          (v4/*: any*/),
                          (v7/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v9/*: any*/),
                      (v25/*: any*/),
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
                      (v2/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v5/*: any*/),
                          (v6/*: any*/),
                          (v4/*: any*/),
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
                      (v2/*: any*/),
                      (v3/*: any*/),
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
                      (v5/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v2/*: any*/),
                          (v6/*: any*/),
                          (v4/*: any*/),
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
                      (v3/*: any*/),
                      (v13/*: any*/),
                      (v10/*: any*/),
                      (v2/*: any*/)
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
                      (v2/*: any*/),
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
                      (v35/*: any*/),
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
                      (v3/*: any*/),
                      (v13/*: any*/),
                      (v35/*: any*/),
                      (v2/*: any*/)
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
    "id": "9d1f3804e9e454cb0a0199b36b10a695",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.codeOfConductFileUrl": (v36/*: any*/),
        "repository.contributingFileUrl": (v36/*: any*/),
        "repository.id": (v37/*: any*/),
        "repository.issue": (v38/*: any*/),
        "repository.issue.__isComment": (v39/*: any*/),
        "repository.issue.blockedBy": (v40/*: any*/),
        "repository.issue.blockedBy.nodes": (v41/*: any*/),
        "repository.issue.blockedBy.nodes.id": (v37/*: any*/),
        "repository.issue.blockedBy.nodes.number": (v42/*: any*/),
        "repository.issue.blockedBy.nodes.repository": (v43/*: any*/),
        "repository.issue.blockedBy.nodes.repository.id": (v37/*: any*/),
        "repository.issue.blockedBy.nodes.repository.name": (v39/*: any*/),
        "repository.issue.blockedBy.nodes.repository.owner": (v44/*: any*/),
        "repository.issue.blockedBy.nodes.repository.owner.__typename": (v39/*: any*/),
        "repository.issue.blockedBy.nodes.repository.owner.id": (v37/*: any*/),
        "repository.issue.blockedBy.nodes.repository.owner.login": (v39/*: any*/),
        "repository.issue.blockedBy.nodes.title": (v39/*: any*/),
        "repository.issue.blockedBy.nodes.url": (v45/*: any*/),
        "repository.issue.closedByPullRequestsReferences": (v46/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes": (v47/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.__typename": (v39/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "repository.issue.closedByPullRequestsReferences.nodes.id": (v37/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.isDraft": (v48/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.isInMergeQueue": (v48/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.number": (v42/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository": (v43/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.id": (v37/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.name": (v39/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner": (v44/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.__typename": (v39/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.id": (v37/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.repository.owner.login": (v39/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.state": (v49/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.title": (v39/*: any*/),
        "repository.issue.closedByPullRequestsReferences.nodes.url": (v45/*: any*/),
        "repository.issue.databaseId": (v50/*: any*/),
        "repository.issue.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "repository.issue.discussion.id": (v37/*: any*/),
        "repository.issue.discussion.url": (v45/*: any*/),
        "repository.issue.duplicateIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueConnection"
        },
        "repository.issue.duplicateIssues.nodes": (v41/*: any*/),
        "repository.issue.duplicateIssues.nodes.id": (v37/*: any*/),
        "repository.issue.duplicateIssues.nodes.number": (v42/*: any*/),
        "repository.issue.duplicateIssues.nodes.repository": (v43/*: any*/),
        "repository.issue.duplicateIssues.nodes.repository.id": (v37/*: any*/),
        "repository.issue.duplicateIssues.nodes.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.duplicateIssues.nodes.state": (v51/*: any*/),
        "repository.issue.duplicateIssues.nodes.stateReason": (v52/*: any*/),
        "repository.issue.duplicateIssues.nodes.title": (v39/*: any*/),
        "repository.issue.duplicateIssues.nodes.url": (v45/*: any*/),
        "repository.issue.id": (v37/*: any*/),
        "repository.issue.isTransferInProgress": (v48/*: any*/),
        "repository.issue.issueDependenciesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueDependenciesSummary"
        },
        "repository.issue.issueDependenciesSummary.blockedBy": (v42/*: any*/),
        "repository.issue.issueDependenciesSummary.blocking": (v42/*: any*/),
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
        "repository.issue.lastUserContentEdit.editor.__typename": (v39/*: any*/),
        "repository.issue.lastUserContentEdit.editor.id": (v37/*: any*/),
        "repository.issue.lastUserContentEdit.editor.login": (v39/*: any*/),
        "repository.issue.lastUserContentEdit.editor.url": (v45/*: any*/),
        "repository.issue.lastUserContentEdit.id": (v37/*: any*/),
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
        "repository.issue.linkedBranches.nodes.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref": (v53/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.__typename": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.associatedPullRequests": (v54/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.associatedPullRequests.totalCount": (v42/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.name": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository": (v43/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef": (v53/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests": (v54/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.associatedPullRequests.totalCount": (v42/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.name": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.repository": (v43/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.repository.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target": (v55/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.__typename": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.defaultBranchRef.target.oid": (v56/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target": (v55/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.__typename": (v39/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.id": (v37/*: any*/),
        "repository.issue.linkedBranches.nodes.ref.target.oid": (v56/*: any*/),
        "repository.issue.linkedPullRequests": (v46/*: any*/),
        "repository.issue.linkedPullRequests.nodes": (v47/*: any*/),
        "repository.issue.linkedPullRequests.nodes.id": (v37/*: any*/),
        "repository.issue.linkedPullRequests.nodes.isDraft": (v48/*: any*/),
        "repository.issue.linkedPullRequests.nodes.number": (v42/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository": (v43/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.id": (v37/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.name": (v39/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner": (v44/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.__typename": (v39/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.id": (v37/*: any*/),
        "repository.issue.linkedPullRequests.nodes.repository.owner.login": (v39/*: any*/),
        "repository.issue.linkedPullRequests.nodes.state": (v49/*: any*/),
        "repository.issue.linkedPullRequests.nodes.url": (v45/*: any*/),
        "repository.issue.number": (v42/*: any*/),
        "repository.issue.parent": (v38/*: any*/),
        "repository.issue.parent.id": (v37/*: any*/),
        "repository.issue.parent.number": (v42/*: any*/),
        "repository.issue.parent.repository": (v43/*: any*/),
        "repository.issue.parent.repository.id": (v37/*: any*/),
        "repository.issue.parent.repository.name": (v39/*: any*/),
        "repository.issue.parent.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.parent.repository.owner": (v44/*: any*/),
        "repository.issue.parent.repository.owner.__typename": (v39/*: any*/),
        "repository.issue.parent.repository.owner.id": (v37/*: any*/),
        "repository.issue.parent.repository.owner.login": (v39/*: any*/),
        "repository.issue.parent.state": (v51/*: any*/),
        "repository.issue.parent.stateReason": (v52/*: any*/),
        "repository.issue.parent.subIssuesSummary": (v57/*: any*/),
        "repository.issue.parent.subIssuesSummary.completed": (v42/*: any*/),
        "repository.issue.parent.subIssuesSummary.total": (v42/*: any*/),
        "repository.issue.parent.title": (v39/*: any*/),
        "repository.issue.parent.titleHTML": (v39/*: any*/),
        "repository.issue.parent.url": (v45/*: any*/),
        "repository.issue.participants": (v58/*: any*/),
        "repository.issue.participants.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "repository.issue.participants.nodes.__isActor": (v39/*: any*/),
        "repository.issue.participants.nodes.__typename": (v39/*: any*/),
        "repository.issue.participants.nodes.avatarUrl": (v45/*: any*/),
        "repository.issue.participants.nodes.id": (v37/*: any*/),
        "repository.issue.participants.nodes.isCopilot": (v48/*: any*/),
        "repository.issue.participants.nodes.login": (v39/*: any*/),
        "repository.issue.participants.nodes.name": (v59/*: any*/),
        "repository.issue.participants.nodes.profileResourcePath": (v36/*: any*/),
        "repository.issue.participants.totalCount": (v42/*: any*/),
        "repository.issue.repository": (v43/*: any*/),
        "repository.issue.repository.databaseId": (v50/*: any*/),
        "repository.issue.repository.id": (v37/*: any*/),
        "repository.issue.repository.isArchived": (v48/*: any*/),
        "repository.issue.repository.name": (v39/*: any*/),
        "repository.issue.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.repository.owner": (v44/*: any*/),
        "repository.issue.repository.owner.__typename": (v39/*: any*/),
        "repository.issue.repository.owner.id": (v37/*: any*/),
        "repository.issue.repository.owner.login": (v39/*: any*/),
        "repository.issue.repository.slashCommandsEnabled": (v48/*: any*/),
        "repository.issue.repository.viewerCanPinIssues": (v48/*: any*/),
        "repository.issue.showSpammyBadge": (v48/*: any*/),
        "repository.issue.state": (v51/*: any*/),
        "repository.issue.subIssues": (v40/*: any*/),
        "repository.issue.subIssues.nodes": (v41/*: any*/),
        "repository.issue.subIssues.nodes.assignees": (v58/*: any*/),
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
        "repository.issue.subIssues.nodes.assignees.edges.node.avatarUrl": (v45/*: any*/),
        "repository.issue.subIssues.nodes.assignees.edges.node.id": (v37/*: any*/),
        "repository.issue.subIssues.nodes.assignees.edges.node.login": (v39/*: any*/),
        "repository.issue.subIssues.nodes.assignees.totalCount": (v42/*: any*/),
        "repository.issue.subIssues.nodes.closed": (v48/*: any*/),
        "repository.issue.subIssues.nodes.closedByPullRequestsReferences": (v46/*: any*/),
        "repository.issue.subIssues.nodes.closedByPullRequestsReferences.totalCount": (v42/*: any*/),
        "repository.issue.subIssues.nodes.databaseId": (v50/*: any*/),
        "repository.issue.subIssues.nodes.id": (v37/*: any*/),
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
        "repository.issue.subIssues.nodes.issueType.id": (v37/*: any*/),
        "repository.issue.subIssues.nodes.issueType.name": (v39/*: any*/),
        "repository.issue.subIssues.nodes.number": (v42/*: any*/),
        "repository.issue.subIssues.nodes.repository": (v43/*: any*/),
        "repository.issue.subIssues.nodes.repository.id": (v37/*: any*/),
        "repository.issue.subIssues.nodes.repository.name": (v39/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner": (v44/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner.__typename": (v39/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner.id": (v37/*: any*/),
        "repository.issue.subIssues.nodes.repository.owner.login": (v39/*: any*/),
        "repository.issue.subIssues.nodes.state": (v51/*: any*/),
        "repository.issue.subIssues.nodes.stateReason": (v52/*: any*/),
        "repository.issue.subIssues.nodes.subIssuesSummary": (v57/*: any*/),
        "repository.issue.subIssues.nodes.subIssuesSummary.completed": (v42/*: any*/),
        "repository.issue.subIssues.nodes.subIssuesSummary.total": (v42/*: any*/),
        "repository.issue.subIssues.nodes.title": (v39/*: any*/),
        "repository.issue.subIssues.nodes.titleHTML": (v39/*: any*/),
        "repository.issue.subIssues.nodes.url": (v45/*: any*/),
        "repository.issue.subIssuesConnection": (v40/*: any*/),
        "repository.issue.subIssuesConnection.totalCount": (v42/*: any*/),
        "repository.issue.suggestedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "repository.issue.suggestedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "repository.issue.suggestedActors.nodes.__isActor": (v39/*: any*/),
        "repository.issue.suggestedActors.nodes.__isNode": (v39/*: any*/),
        "repository.issue.suggestedActors.nodes.__typename": (v39/*: any*/),
        "repository.issue.suggestedActors.nodes.avatarUrl": (v45/*: any*/),
        "repository.issue.suggestedActors.nodes.id": (v37/*: any*/),
        "repository.issue.suggestedActors.nodes.isCopilot": (v48/*: any*/),
        "repository.issue.suggestedActors.nodes.login": (v39/*: any*/),
        "repository.issue.suggestedActors.nodes.name": (v59/*: any*/),
        "repository.issue.suggestedActors.nodes.profileResourcePath": (v36/*: any*/),
        "repository.issue.taskListSummary": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TaskListSummary"
        },
        "repository.issue.taskListSummary.completeCount": (v42/*: any*/),
        "repository.issue.taskListSummary.itemCount": (v42/*: any*/),
        "repository.issue.tasklistBlocksCompletion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "TrackedIssueCompletion"
        },
        "repository.issue.tasklistBlocksCompletion.completed": (v42/*: any*/),
        "repository.issue.tasklistBlocksCompletion.total": (v42/*: any*/),
        "repository.issue.threadSubscriptionChannel": (v59/*: any*/),
        "repository.issue.title": (v39/*: any*/),
        "repository.issue.topBlockedBy": (v40/*: any*/),
        "repository.issue.topBlockedBy.nodes": (v41/*: any*/),
        "repository.issue.topBlockedBy.nodes.id": (v37/*: any*/),
        "repository.issue.topBlockedBy.nodes.number": (v42/*: any*/),
        "repository.issue.topBlockedBy.nodes.repository": (v43/*: any*/),
        "repository.issue.topBlockedBy.nodes.repository.id": (v37/*: any*/),
        "repository.issue.topBlockedBy.nodes.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.topBlockedBy.nodes.state": (v51/*: any*/),
        "repository.issue.topBlockedBy.nodes.stateReason": (v52/*: any*/),
        "repository.issue.topBlockedBy.nodes.title": (v39/*: any*/),
        "repository.issue.topBlockedBy.nodes.titleHTML": (v39/*: any*/),
        "repository.issue.topBlockedBy.nodes.url": (v45/*: any*/),
        "repository.issue.topBlockedBy.pageInfo": (v60/*: any*/),
        "repository.issue.topBlockedBy.pageInfo.hasNextPage": (v48/*: any*/),
        "repository.issue.topBlocking": (v40/*: any*/),
        "repository.issue.topBlocking.nodes": (v41/*: any*/),
        "repository.issue.topBlocking.nodes.id": (v37/*: any*/),
        "repository.issue.topBlocking.nodes.number": (v42/*: any*/),
        "repository.issue.topBlocking.nodes.repository": (v43/*: any*/),
        "repository.issue.topBlocking.nodes.repository.id": (v37/*: any*/),
        "repository.issue.topBlocking.nodes.repository.nameWithOwner": (v39/*: any*/),
        "repository.issue.topBlocking.nodes.state": (v51/*: any*/),
        "repository.issue.topBlocking.nodes.stateReason": (v52/*: any*/),
        "repository.issue.topBlocking.nodes.title": (v39/*: any*/),
        "repository.issue.topBlocking.nodes.titleHTML": (v39/*: any*/),
        "repository.issue.topBlocking.nodes.url": (v45/*: any*/),
        "repository.issue.topBlocking.pageInfo": (v60/*: any*/),
        "repository.issue.topBlocking.pageInfo.hasNextPage": (v48/*: any*/),
        "repository.issue.trackedInIssues": (v40/*: any*/),
        "repository.issue.trackedInIssues.nodes": (v41/*: any*/),
        "repository.issue.trackedInIssues.nodes.id": (v37/*: any*/),
        "repository.issue.trackedInIssues.nodes.number": (v42/*: any*/),
        "repository.issue.trackedInIssues.nodes.stateReason": (v52/*: any*/),
        "repository.issue.trackedInIssues.nodes.url": (v45/*: any*/),
        "repository.issue.trackedInIssues.totalCount": (v42/*: any*/),
        "repository.issue.url": (v45/*: any*/),
        "repository.issue.viewerCanBlockFromOrg": (v48/*: any*/),
        "repository.issue.viewerCanClose": (v48/*: any*/),
        "repository.issue.viewerCanConvertToDiscussion": (v61/*: any*/),
        "repository.issue.viewerCanDelete": (v48/*: any*/),
        "repository.issue.viewerCanLinkBranches": (v48/*: any*/),
        "repository.issue.viewerCanLock": (v61/*: any*/),
        "repository.issue.viewerCanReadUserContentEdits": (v48/*: any*/),
        "repository.issue.viewerCanReopen": (v48/*: any*/),
        "repository.issue.viewerCanReport": (v48/*: any*/),
        "repository.issue.viewerCanReportToMaintainer": (v48/*: any*/),
        "repository.issue.viewerCanTransfer": (v48/*: any*/),
        "repository.issue.viewerCanType": (v61/*: any*/),
        "repository.issue.viewerCanUnblockFromOrg": (v48/*: any*/),
        "repository.issue.viewerCanUpdateMetadata": (v61/*: any*/),
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
        "repository.securityPolicyUrl": (v36/*: any*/),
        "repository.supportFileUrl": (v36/*: any*/)
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
