/**
 * @generated SignedSource<<c60a5171352aff269de9ca7d2b29a744>>
 * @relayHash 4db037b5448b0c3497dcb96fa9338d49
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4db037b5448b0c3497dcb96fa9338d49

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssuesSubscription_IssueViewerSubscription$variables = {
  issueId: string;
};
export type SubIssuesSubscription_IssueViewerSubscription$data = {
  readonly issueUpdated: {
    readonly subIssuesUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesList">;
    } | null | undefined;
  };
};
export type SubIssuesSubscription_IssueViewerSubscription = {
  response: SubIssuesSubscription_IssueViewerSubscription$data;
  variables: SubIssuesSubscription_IssueViewerSubscription$variables;
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
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    },
    (v4/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v7 = [
  (v6/*: any*/)
],
v8 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Issue"
},
v9 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Repository"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v12 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "RepositoryOwner"
},
v13 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "IssueConnection"
},
v14 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v15 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "SubIssuesSubscription_IssueViewerSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssuesUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "SubIssuesList"
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "SubIssuesSubscription_IssueViewerSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssuesUpdated",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v3/*: any*/),
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "nameWithOwner",
                    "storageKey": null
                  },
                  (v5/*: any*/)
                ],
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
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "state",
                        "storageKey": null
                      },
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
                      {
                        "alias": null,
                        "args": [
                          {
                            "kind": "Literal",
                            "name": "first",
                            "value": 10
                          }
                        ],
                        "concreteType": "UserConnection",
                        "kind": "LinkedField",
                        "name": "assignees",
                        "plural": false,
                        "selections": [
                          (v6/*: any*/),
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
                                  (v4/*: any*/),
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
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "url",
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
                          (v2/*: any*/)
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
                        "name": "title",
                        "storageKey": null
                      },
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
                        "concreteType": "IssueType",
                        "kind": "LinkedField",
                        "name": "issueType",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          (v3/*: any*/),
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
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "SubIssuesSummary",
                        "kind": "LinkedField",
                        "name": "subIssuesSummary",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "total",
                            "storageKey": null
                          },
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
                        "selections": (v7/*: any*/),
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
                "selections": (v7/*: any*/),
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
    ]
  },
  "params": {
    "id": "4db037b5448b0c3497dcb96fa9338d49",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.subIssuesUpdated": (v8/*: any*/),
        "issueUpdated.subIssuesUpdated.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.parent": (v8/*: any*/),
        "issueUpdated.subIssuesUpdated.parent.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.repository": (v10/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.name": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.nameWithOwner": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner": (v12/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner.__typename": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.repository.owner.login": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Issue"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "UserConnection"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "UserEdge"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "User"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees.edges.node.avatarUrl": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees.edges.node.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees.edges.node.login": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.assignees.totalCount": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.closed": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.closedByPullRequestsReferences": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PullRequestConnection"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.closedByPullRequestsReferences.totalCount": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.databaseId": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Int"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.issueType": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueType"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.issueType.color": {
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
        "issueUpdated.subIssuesUpdated.subIssues.nodes.issueType.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.issueType.name": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.number": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository": (v10/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository.name": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository.owner": (v12/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository.owner.__typename": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository.owner.id": (v9/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.repository.owner.login": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueState"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.stateReason": {
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
        "issueUpdated.subIssuesUpdated.subIssues.nodes.subIssuesSummary": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "SubIssuesSummary"
        },
        "issueUpdated.subIssuesUpdated.subIssues.nodes.subIssuesSummary.completed": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.subIssuesSummary.total": (v15/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.title": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.titleHTML": (v11/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssues.nodes.url": (v14/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssuesConnection": (v13/*: any*/),
        "issueUpdated.subIssuesUpdated.subIssuesConnection.totalCount": (v15/*: any*/)
      }
    },
    "name": "SubIssuesSubscription_IssueViewerSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "c6109d909ad88cecb13468b972ec7f74";

export default node;
