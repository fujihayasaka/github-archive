/**
 * @generated SignedSource<<d614935310a30b3c7adceb343fd7c635>>
 * @relayHash f0758cf0b070b22cc3805144ae9c1873
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f0758cf0b070b22cc3805144ae9c1873

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type IssueTypeColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
export type ConvertChecklistItemToSubIssueInput = {
  body?: string | null | undefined;
  clientMutationId?: string | null | undefined;
  parentIssueId: string;
  position: ReadonlyArray<number>;
  repositoryId: string;
  title?: string | null | undefined;
};
export type createSubIssueFromChecklistItemMutation$variables = {
  input: ConvertChecklistItemToSubIssueInput;
};
export type createSubIssueFromChecklistItemMutation$data = {
  readonly convertChecklistItemToSubIssue: {
    readonly errors: ReadonlyArray<{
      readonly message: string;
    }>;
    readonly issue: {
      readonly id: string;
      readonly parent: {
        readonly body: string;
        readonly bodyHTML: string;
        readonly id: string;
        readonly " $fragmentSpreads": FragmentRefs<"SubIssuesList">;
      } | null | undefined;
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined;
  } | null | undefined;
};
export type createSubIssueFromChecklistItemMutation$rawResponse = {
  readonly convertChecklistItemToSubIssue: {
    readonly errors: ReadonlyArray<{
      readonly __typename: string;
      readonly message: string;
    }>;
    readonly issue: {
      readonly assignees: {
        readonly edges: ReadonlyArray<{
          readonly node: {
            readonly avatarUrl: string;
            readonly id: string;
            readonly login: string;
          } | null | undefined;
        } | null | undefined> | null | undefined;
        readonly totalCount: number;
      };
      readonly closedByPullRequestsReferences: {
        readonly totalCount: number;
      } | null | undefined;
      readonly databaseId: number | null | undefined;
      readonly id: string;
      readonly issueType: {
        readonly color: IssueTypeColor;
        readonly id: string;
        readonly name: string;
      } | null | undefined;
      readonly number: number;
      readonly parent: {
        readonly body: string;
        readonly bodyHTML: string;
        readonly id: string;
        readonly parent: {
          readonly id: string;
        } | null | undefined;
        readonly repository: {
          readonly id: string;
          readonly name: string;
          readonly nameWithOwner: string;
          readonly owner: {
            readonly __typename: string;
            readonly id: string;
            readonly login: string;
          };
        };
        readonly subIssues: {
          readonly nodes: ReadonlyArray<{
            readonly assignees: {
              readonly edges: ReadonlyArray<{
                readonly node: {
                  readonly avatarUrl: string;
                  readonly id: string;
                  readonly login: string;
                } | null | undefined;
              } | null | undefined> | null | undefined;
              readonly totalCount: number;
            };
            readonly closed: boolean;
            readonly closedByPullRequestsReferences: {
              readonly totalCount: number;
            } | null | undefined;
            readonly databaseId: number | null | undefined;
            readonly id: string;
            readonly issueType: {
              readonly color: IssueTypeColor;
              readonly id: string;
              readonly name: string;
            } | null | undefined;
            readonly number: number;
            readonly repository: {
              readonly id: string;
              readonly name: string;
              readonly owner: {
                readonly __typename: string;
                readonly id: string;
                readonly login: string;
              };
            };
            readonly state: IssueState;
            readonly stateReason: IssueStateReason | null | undefined;
            readonly subIssuesSummary: {
              readonly completed: number;
              readonly total: number;
            };
            readonly title: string;
            readonly titleHTML: string;
            readonly url: string;
          } | null | undefined> | null | undefined;
        };
        readonly subIssuesConnection: {
          readonly totalCount: number;
        };
      } | null | undefined;
      readonly repository: {
        readonly id: string;
        readonly name: string;
        readonly owner: {
          readonly __typename: string;
          readonly id: string;
          readonly login: string;
        };
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly subIssuesSummary: {
        readonly completed: number;
        readonly total: number;
      };
      readonly title: string;
      readonly titleHTML: string;
      readonly url: string;
    } | null | undefined;
  } | null | undefined;
};
export type createSubIssueFromChecklistItemMutation = {
  rawResponse: createSubIssueFromChecklistItemMutation$rawResponse;
  response: createSubIssueFromChecklistItemMutation$data;
  variables: createSubIssueFromChecklistItemMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
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
  "name": "body",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "renderTasklistBlocks",
      "value": true
    },
    {
      "kind": "Literal",
      "name": "unfurlReferences",
      "value": true
    }
  ],
  "kind": "ScalarField",
  "name": "bodyHTML",
  "storageKey": "bodyHTML(renderTasklistBlocks:true,unfurlReferences:true)"
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "message",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "concreteType": null,
  "kind": "LinkedField",
  "name": "owner",
  "plural": false,
  "selections": [
    (v7/*: any*/),
    (v8/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v11 = {
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
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "totalCount",
  "storageKey": null
},
v13 = {
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
            (v2/*: any*/),
            (v8/*: any*/),
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
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v6/*: any*/),
    (v9/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
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
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "issueType",
  "plural": false,
  "selections": [
    (v2/*: any*/),
    (v6/*: any*/),
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
v21 = {
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
v22 = [
  (v12/*: any*/)
],
v23 = {
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
  "selections": (v22/*: any*/),
  "storageKey": "closedByPullRequestsReferences(first:0,includeClosedPrs:true)"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "createSubIssueFromChecklistItemMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ConvertChecklistItemToSubIssuePayload",
        "kind": "LinkedField",
        "name": "convertChecklistItemToSubIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
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
                  (v4/*: any*/),
                  {
                    "args": null,
                    "kind": "FragmentSpread",
                    "name": "SubIssuesList"
                  }
                ],
                "storageKey": null
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "SubIssuesListItem"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "errors",
            "plural": true,
            "selections": [
              (v5/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "createSubIssueFromChecklistItemMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "ConvertChecklistItemToSubIssuePayload",
        "kind": "LinkedField",
        "name": "convertChecklistItemToSubIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v2/*: any*/),
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
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Repository",
                    "kind": "LinkedField",
                    "name": "repository",
                    "plural": false,
                    "selections": [
                      (v6/*: any*/),
                      (v2/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "nameWithOwner",
                        "storageKey": null
                      },
                      (v9/*: any*/)
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
                          (v10/*: any*/),
                          (v11/*: any*/),
                          (v13/*: any*/),
                          (v14/*: any*/),
                          (v15/*: any*/),
                          (v16/*: any*/),
                          (v17/*: any*/),
                          (v18/*: any*/),
                          (v19/*: any*/),
                          (v20/*: any*/),
                          (v21/*: any*/),
                          (v23/*: any*/),
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
                    "selections": (v22/*: any*/),
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
              },
              (v10/*: any*/),
              (v11/*: any*/),
              (v13/*: any*/),
              (v14/*: any*/),
              (v15/*: any*/),
              (v16/*: any*/),
              (v17/*: any*/),
              (v18/*: any*/),
              (v19/*: any*/),
              (v20/*: any*/),
              (v21/*: any*/),
              (v23/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "errors",
            "plural": true,
            "selections": [
              (v7/*: any*/),
              (v5/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "f0758cf0b070b22cc3805144ae9c1873",
    "metadata": {},
    "name": "createSubIssueFromChecklistItemMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "79e6ef2540717d803212087083925e1b";

export default node;
