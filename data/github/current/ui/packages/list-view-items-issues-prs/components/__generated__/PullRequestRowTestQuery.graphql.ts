/**
 * @generated SignedSource<<d7bd61428d70e5de7ae79e196d1a3d98>>
 * @relayHash 8c348261fb11e2265208e8beb9bfcb4f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 8c348261fb11e2265208e8beb9bfcb4f

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PullRequestState = "CLOSED" | "MERGED" | "OPEN" | "%future added value";
export type PullRequestRowTestQuery$variables = {
  id: string;
};
export type PullRequestRowTestQuery$data = {
  readonly pullRequest: {
    readonly __typename: "PullRequest";
    readonly pullRequestState: PullRequestState;
    readonly " $fragmentSpreads": FragmentRefs<"PullRequestRow_pullRequest">;
  } | {
    // This will never be '%other', but we need some
    // value in case none of the concrete values match.
    readonly __typename: "%other";
  } | null | undefined;
};
export type PullRequestRowTestQuery = {
  response: PullRequestRowTestQuery$data;
  variables: PullRequestRowTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
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
  "alias": "pullRequestState",
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
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
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "concreteType": "StatusCheckRollup",
  "kind": "LinkedField",
  "name": "statusCheckRollup",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "StatusCheckRollupContextConnection",
      "kind": "LinkedField",
      "name": "contexts",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "checkRunCount",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "CheckRunStateCount",
          "kind": "LinkedField",
          "name": "checkRunCountsByState",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "count",
              "storageKey": null
            },
            (v7/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    (v4/*: any*/)
  ],
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "first",
      "value": 5
    },
    {
      "kind": "Literal",
      "name": "orderBy",
      "value": {
        "direction": "ASC",
        "field": "NAME"
      }
    }
  ],
  "concreteType": "LabelConnection",
  "kind": "LinkedField",
  "name": "labels",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "Label",
      "kind": "LinkedField",
      "name": "nodes",
      "plural": true,
      "selections": [
        (v4/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameHTML",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "color",
          "storageKey": null
        },
        (v5/*: any*/),
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
  "storageKey": "labels(first:5,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "createdAt",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "updatedAt",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closedAt",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "author",
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
    },
    (v4/*: any*/)
  ],
  "storageKey": null
},
v16 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Milestone",
    "kind": "LinkedField",
    "name": "milestone",
    "plural": false,
    "selections": [
      (v9/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "url",
        "storageKey": null
      },
      (v4/*: any*/)
    ],
    "storageKey": null
  }
],
v17 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": (v16/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v16/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
},
v18 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v19 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v20 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v21 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "DateTime"
},
v23 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "StatusCheckRollup"
},
v24 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "StatusCheckRollupContextConnection"
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
  "plural": true,
  "type": "CheckRunStateCount"
},
v27 = {
  "enumValues": [
    "ACTION_REQUIRED",
    "CANCELLED",
    "COMPLETED",
    "FAILURE",
    "IN_PROGRESS",
    "NEUTRAL",
    "PENDING",
    "QUEUED",
    "SKIPPED",
    "STALE",
    "STARTUP_FAILURE",
    "SUCCESS",
    "TIMED_OUT",
    "WAITING"
  ],
  "nullable": false,
  "plural": false,
  "type": "CheckRunState"
},
v28 = {
  "enumValues": [
    "ERROR",
    "EXPECTED",
    "FAILURE",
    "PENDING",
    "SUCCESS"
  ],
  "nullable": false,
  "plural": false,
  "type": "StatusState"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "PullRequestRowTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": [
                  {
                    "kind": "Literal",
                    "name": "labelPageSize",
                    "value": 5
                  }
                ],
                "kind": "FragmentSpread",
                "name": "PullRequestRow_pullRequest"
              },
              (v3/*: any*/)
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "PullRequestRowTestQuery",
    "selections": [
      {
        "alias": "pullRequest",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v4/*: any*/),
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
                "selections": [
                  (v5/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      (v6/*: any*/),
                      (v4/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v4/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "PullRequestCommit",
                "kind": "LinkedField",
                "name": "headCommit",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Commit",
                    "kind": "LinkedField",
                    "name": "commit",
                    "plural": false,
                    "selections": [
                      (v4/*: any*/),
                      (v8/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v4/*: any*/)
                ],
                "storageKey": null
              },
              (v8/*: any*/),
              (v9/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "titleHTML",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "number",
                "storageKey": null
              },
              (v3/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v10/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      (v13/*: any*/),
                      (v14/*: any*/),
                      (v15/*: any*/),
                      {
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
                      (v7/*: any*/),
                      (v17/*: any*/)
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v10/*: any*/),
                      (v11/*: any*/),
                      (v12/*: any*/),
                      (v13/*: any*/),
                      (v14/*: any*/),
                      (v15/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "reviewDecision",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isDraft",
                        "storageKey": null
                      },
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "isInMergeQueue",
                        "storageKey": null
                      },
                      (v17/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              }
            ],
            "type": "PullRequest",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "8c348261fb11e2265208e8beb9bfcb4f",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "pullRequest": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "pullRequest.__isIssueOrPullRequest": (v18/*: any*/),
        "pullRequest.__typename": (v18/*: any*/),
        "pullRequest.author": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "pullRequest.author.__typename": (v18/*: any*/),
        "pullRequest.author.avatarUrl": (v19/*: any*/),
        "pullRequest.author.id": (v20/*: any*/),
        "pullRequest.author.login": (v18/*: any*/),
        "pullRequest.closed": (v21/*: any*/),
        "pullRequest.closedAt": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "pullRequest.createdAt": (v22/*: any*/),
        "pullRequest.headCommit": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestCommit"
        },
        "pullRequest.headCommit.commit": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Commit"
        },
        "pullRequest.headCommit.commit.id": (v20/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup": (v23/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.contexts": (v24/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.contexts.checkRunCount": (v25/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState": (v26/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState.count": (v25/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.contexts.checkRunCountsByState.state": (v27/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.id": (v20/*: any*/),
        "pullRequest.headCommit.commit.statusCheckRollup.state": (v28/*: any*/),
        "pullRequest.headCommit.id": (v20/*: any*/),
        "pullRequest.id": (v20/*: any*/),
        "pullRequest.isDraft": (v21/*: any*/),
        "pullRequest.isInMergeQueue": (v21/*: any*/),
        "pullRequest.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "pullRequest.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "pullRequest.labels.nodes.color": (v18/*: any*/),
        "pullRequest.labels.nodes.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "pullRequest.labels.nodes.id": (v20/*: any*/),
        "pullRequest.labels.nodes.name": (v18/*: any*/),
        "pullRequest.labels.nodes.nameHTML": (v18/*: any*/),
        "pullRequest.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "pullRequest.milestone.id": (v20/*: any*/),
        "pullRequest.milestone.title": (v18/*: any*/),
        "pullRequest.milestone.url": (v19/*: any*/),
        "pullRequest.number": (v25/*: any*/),
        "pullRequest.pullRequestState": {
          "enumValues": [
            "CLOSED",
            "MERGED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "PullRequestState"
        },
        "pullRequest.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "pullRequest.repository.id": (v20/*: any*/),
        "pullRequest.repository.name": (v18/*: any*/),
        "pullRequest.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "pullRequest.repository.owner.__typename": (v18/*: any*/),
        "pullRequest.repository.owner.id": (v20/*: any*/),
        "pullRequest.repository.owner.login": (v18/*: any*/),
        "pullRequest.reviewDecision": {
          "enumValues": [
            "APPROVED",
            "CHANGES_REQUESTED",
            "REVIEW_REQUIRED"
          ],
          "nullable": true,
          "plural": false,
          "type": "PullRequestReviewDecision"
        },
        "pullRequest.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "pullRequest.stateReason": {
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
        "pullRequest.statusCheckRollup": (v23/*: any*/),
        "pullRequest.statusCheckRollup.contexts": (v24/*: any*/),
        "pullRequest.statusCheckRollup.contexts.checkRunCount": (v25/*: any*/),
        "pullRequest.statusCheckRollup.contexts.checkRunCountsByState": (v26/*: any*/),
        "pullRequest.statusCheckRollup.contexts.checkRunCountsByState.count": (v25/*: any*/),
        "pullRequest.statusCheckRollup.contexts.checkRunCountsByState.state": (v27/*: any*/),
        "pullRequest.statusCheckRollup.id": (v20/*: any*/),
        "pullRequest.statusCheckRollup.state": (v28/*: any*/),
        "pullRequest.title": (v18/*: any*/),
        "pullRequest.titleHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "pullRequest.updatedAt": (v22/*: any*/)
      }
    },
    "name": "PullRequestRowTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "6c4811abc2ee6bb1690112892707830a";

export default node;
