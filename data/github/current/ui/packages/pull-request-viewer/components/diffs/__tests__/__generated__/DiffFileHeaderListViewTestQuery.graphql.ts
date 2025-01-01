/**
 * @generated SignedSource<<bf6e55fc7a55d59bc6b67493c4b16b35>>
 * @relayHash 842380129aef25800825b4032ca2df36
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 842380129aef25800825b4032ca2df36

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DiffFileHeaderListViewTestQuery$variables = {
  endOid?: string | null | undefined;
  pullRequestId: string;
  singleCommitOid?: string | null | undefined;
  startOid?: string | null | undefined;
};
export type DiffFileHeaderListViewTestQuery$data = {
  readonly pullRequest: {
    readonly comparison?: {
      readonly diffEntries: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"DiffFileHeaderListView_diffEntry">;
        } | null | undefined> | null | undefined;
      };
    } | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"DiffFileHeaderListView_pullRequest">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"DiffFileHeaderListView_viewer">;
  };
};
export type DiffFileHeaderListViewTestQuery = {
  response: DiffFileHeaderListViewTestQuery$data;
  variables: DiffFileHeaderListViewTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "endOid"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "pullRequestId"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "singleCommitOid"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "startOid"
},
v4 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "pullRequestId"
  }
],
v5 = [
  {
    "kind": "Variable",
    "name": "endOid",
    "variableName": "endOid"
  },
  {
    "kind": "Variable",
    "name": "singleCommitOid",
    "variableName": "singleCommitOid"
  },
  {
    "kind": "Variable",
    "name": "startOid",
    "variableName": "startOid"
  }
],
v6 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 20
  }
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "size",
      "value": 48
    }
  ],
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": "avatarUrl(size:48)"
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
  "name": "__typename",
  "storageKey": null
},
v11 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameWithOwner",
    "storageKey": null
  },
  (v9/*: any*/)
],
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "path",
  "storageKey": null
},
v13 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "mode",
    "storageKey": null
  },
  (v12/*: any*/)
],
v14 = {
  "kind": "Literal",
  "name": "first",
  "value": 50
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCommentsCount",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isOutdated",
  "storageKey": null
},
v18 = {
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
v19 = {
  "alias": null,
  "args": [
    (v14/*: any*/)
  ],
  "concreteType": "PullRequestReviewCommentConnection",
  "kind": "LinkedField",
  "name": "comments",
  "plural": false,
  "selections": [
    (v15/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "PullRequestReviewCommentEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "PullRequestReviewComment",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "author",
              "plural": false,
              "selections": [
                (v10/*: any*/),
                (v8/*: any*/),
                (v7/*: any*/),
                (v9/*: any*/)
              ],
              "storageKey": null
            },
            (v9/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v18/*: any*/)
  ],
  "storageKey": "comments(first:50)"
},
v20 = [
  (v14/*: any*/),
  {
    "kind": "Literal",
    "name": "subjectType",
    "value": "FILE"
  }
],
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v22 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Repository"
},
v23 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v25 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v26 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "TreeEntry"
},
v27 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v28 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestThreadConnection"
},
v29 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequestThreadEdge"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestThread"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PullRequestReviewCommentConnection"
},
v32 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "PullRequestReviewCommentEdge"
},
v33 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "PullRequestReviewComment"
},
v34 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Actor"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "DiffFileHeaderListViewTestQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "DiffFileHeaderListView_viewer"
          }
        ],
        "storageKey": null
      },
      {
        "alias": "pullRequest",
        "args": (v4/*: any*/),
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
                "name": "DiffFileHeaderListView_pullRequest"
              },
              {
                "alias": null,
                "args": (v5/*: any*/),
                "concreteType": "PullRequestComparison",
                "kind": "LinkedField",
                "name": "comparison",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": (v6/*: any*/),
                    "concreteType": "PullRequestDiffEntryConnection",
                    "kind": "LinkedField",
                    "name": "diffEntries",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestDiffEntry",
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          {
                            "args": null,
                            "kind": "FragmentSpread",
                            "name": "DiffFileHeaderListView_diffEntry"
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "diffEntries(first:20)"
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "PullRequest",
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
    "argumentDefinitions": [
      (v1/*: any*/),
      (v2/*: any*/),
      (v0/*: any*/),
      (v3/*: any*/)
    ],
    "kind": "Operation",
    "name": "DiffFileHeaderListViewTestQuery",
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          (v7/*: any*/),
          (v8/*: any*/),
          (v9/*: any*/)
        ],
        "storageKey": null
      },
      {
        "alias": "pullRequest",
        "args": (v4/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v10/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "number",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "headRefName",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "headRepository",
                "plural": false,
                "selections": (v11/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "baseRepository",
                "plural": false,
                "selections": (v11/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanEditFiles",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v5/*: any*/),
                "concreteType": "PullRequestComparison",
                "kind": "LinkedField",
                "name": "comparison",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": (v6/*: any*/),
                    "concreteType": "PullRequestDiffEntryConnection",
                    "kind": "LinkedField",
                    "name": "diffEntries",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "PullRequestDiffEntry",
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "pathDigest",
                            "storageKey": null
                          },
                          (v12/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "PathOwnership",
                            "kind": "LinkedField",
                            "name": "pathOwnership",
                            "plural": false,
                            "selections": [
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "PathOwner",
                                "kind": "LinkedField",
                                "name": "pathOwners",
                                "plural": true,
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "name",
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "ruleLineNumber",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "ruleUrl",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "isOwnedByViewer",
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "TreeEntry",
                            "kind": "LinkedField",
                            "name": "oldTreeEntry",
                            "plural": false,
                            "selections": (v13/*: any*/),
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "TreeEntry",
                            "kind": "LinkedField",
                            "name": "newTreeEntry",
                            "plural": false,
                            "selections": (v13/*: any*/),
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "status",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "linesAdded",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "linesChanged",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "linesDeleted",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "oid",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isSubmodule",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isBinary",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "isLfsPointer",
                            "storageKey": null
                          },
                          {
                            "alias": "outdatedThreads",
                            "args": [
                              (v14/*: any*/),
                              {
                                "kind": "Literal",
                                "name": "outdatedFilter",
                                "value": "ONLY_OUTDATED"
                              },
                              {
                                "kind": "Literal",
                                "name": "subjectType",
                                "value": "LINE"
                              }
                            ],
                            "concreteType": "PullRequestThreadConnection",
                            "kind": "LinkedField",
                            "name": "threads",
                            "plural": false,
                            "selections": [
                              (v15/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "PullRequestThreadEdge",
                                "kind": "LinkedField",
                                "name": "edges",
                                "plural": true,
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "PullRequestThread",
                                    "kind": "LinkedField",
                                    "name": "node",
                                    "plural": false,
                                    "selections": [
                                      (v9/*: any*/),
                                      (v17/*: any*/),
                                      (v19/*: any*/)
                                    ],
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              },
                              (v18/*: any*/)
                            ],
                            "storageKey": "threads(first:50,outdatedFilter:\"ONLY_OUTDATED\",subjectType:\"LINE\")"
                          },
                          {
                            "alias": null,
                            "args": (v20/*: any*/),
                            "concreteType": "PullRequestThreadConnection",
                            "kind": "LinkedField",
                            "name": "threads",
                            "plural": false,
                            "selections": [
                              (v15/*: any*/),
                              (v16/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "concreteType": "PullRequestThreadEdge",
                                "kind": "LinkedField",
                                "name": "edges",
                                "plural": true,
                                "selections": [
                                  {
                                    "alias": null,
                                    "args": null,
                                    "concreteType": "PullRequestThread",
                                    "kind": "LinkedField",
                                    "name": "node",
                                    "plural": false,
                                    "selections": [
                                      (v9/*: any*/),
                                      (v17/*: any*/),
                                      (v19/*: any*/),
                                      (v10/*: any*/)
                                    ],
                                    "storageKey": null
                                  },
                                  {
                                    "alias": null,
                                    "args": null,
                                    "kind": "ScalarField",
                                    "name": "cursor",
                                    "storageKey": null
                                  }
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
                              (v18/*: any*/)
                            ],
                            "storageKey": "threads(first:50,subjectType:\"FILE\")"
                          },
                          {
                            "alias": null,
                            "args": (v20/*: any*/),
                            "filters": [
                              "subjectType"
                            ],
                            "handle": "connection",
                            "key": "FileConversationsButton_threads",
                            "kind": "LinkedHandle",
                            "name": "threads"
                          },
                          (v9/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "viewerViewedState",
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "diffEntries(first:20)"
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          },
          (v9/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "842380129aef25800825b4032ca2df36",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequest": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequest.__typename": (v21/*: any*/),
        "pullRequest.baseRepository": (v22/*: any*/),
        "pullRequest.baseRepository.id": (v23/*: any*/),
        "pullRequest.baseRepository.nameWithOwner": (v21/*: any*/),
        "pullRequest.comparison": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestComparison"
        },
        "pullRequest.comparison.diffEntries": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PullRequestDiffEntryConnection"
        },
        "pullRequest.comparison.diffEntries.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "PullRequestDiffEntry"
        },
        "pullRequest.comparison.diffEntries.nodes.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.isBinary": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.isLfsPointer": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.isSubmodule": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.linesAdded": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.linesChanged": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.linesDeleted": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.newTreeEntry": (v26/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.newTreeEntry.mode": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.newTreeEntry.path": (v27/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.oid": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.oldTreeEntry": (v26/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.oldTreeEntry.mode": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.oldTreeEntry.path": (v27/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads": (v28/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.__id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges": (v29/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node": (v30/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments": (v31/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.__id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges": (v32/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node": (v33/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node.author": (v34/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node.author.__typename": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node.author.avatarUrl": (v35/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node.author.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node.author.login": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.edges.node.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.comments.totalCount": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.edges.node.isOutdated": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.totalCommentsCount": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.outdatedThreads.totalCount": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.path": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.pathDigest": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.pathOwnership": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PathOwnership"
        },
        "pullRequest.comparison.diffEntries.nodes.pathOwnership.isOwnedByViewer": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.pathOwnership.pathOwners": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "PathOwner"
        },
        "pullRequest.comparison.diffEntries.nodes.pathOwnership.pathOwners.name": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.pathOwnership.ruleLineNumber": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Int"
        },
        "pullRequest.comparison.diffEntries.nodes.pathOwnership.ruleUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "pullRequest.comparison.diffEntries.nodes.status": {
          "enumValues": [
            "ADDED",
            "CHANGED",
            "COPIED",
            "DELETED",
            "MODIFIED",
            "RENAMED"
          ],
          "nullable": false,
          "plural": false,
          "type": "PatchStatus"
        },
        "pullRequest.comparison.diffEntries.nodes.threads": (v28/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.__id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges": (v29/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.cursor": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node": (v30/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.__typename": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments": (v31/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.__id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges": (v32/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node": (v33/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node.author": (v34/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node.author.__typename": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node.author.avatarUrl": (v35/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node.author.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node.author.login": (v21/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.edges.node.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.comments.totalCount": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.id": (v23/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.edges.node.isOutdated": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "pullRequest.comparison.diffEntries.nodes.threads.pageInfo.endCursor": (v27/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.pageInfo.hasNextPage": (v24/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.totalCommentsCount": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.threads.totalCount": (v25/*: any*/),
        "pullRequest.comparison.diffEntries.nodes.viewerViewedState": {
          "enumValues": [
            "DISMISSED",
            "UNVIEWED",
            "VIEWED"
          ],
          "nullable": true,
          "plural": false,
          "type": "FileViewedState"
        },
        "pullRequest.headRefName": (v21/*: any*/),
        "pullRequest.headRepository": (v22/*: any*/),
        "pullRequest.headRepository.id": (v23/*: any*/),
        "pullRequest.headRepository.nameWithOwner": (v21/*: any*/),
        "pullRequest.id": (v23/*: any*/),
        "pullRequest.number": (v25/*: any*/),
        "pullRequest.viewerCanEditFiles": (v24/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.avatarUrl": (v35/*: any*/),
        "viewer.id": (v23/*: any*/),
        "viewer.login": (v21/*: any*/)
      }
    },
    "name": "DiffFileHeaderListViewTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "576ccf58916a0ee06aabc4e7e61a66a8";

export default node;
