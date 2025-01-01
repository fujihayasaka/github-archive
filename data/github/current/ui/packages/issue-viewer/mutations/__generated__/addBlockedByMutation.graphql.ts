/**
 * @generated SignedSource<<79055af2ff1fe12e57d8f93d6237277f>>
 * @relayHash 7b226e33d51daf610c78cb8637f67eec
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7b226e33d51daf610c78cb8637f67eec

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type AddBlockedByInput = {
  blockingIssueId: string;
  clientMutationId?: string | null | undefined;
  issueId: string;
};
export type addBlockedByMutation$variables = {
  input: AddBlockedByInput;
};
export type addBlockedByMutation$data = {
  readonly addBlockedBy: {
    readonly blockingIssue: {
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly nameWithOwner: string;
      };
      readonly title: string;
      readonly " $fragmentSpreads": FragmentRefs<"RelationshipsSectionFragment">;
    } | null | undefined;
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"RelationshipsSectionFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type addBlockedByMutation$rawResponse = {
  readonly addBlockedBy: {
    readonly blockingIssue: {
      readonly id: string;
      readonly issueDependenciesSummary: {
        readonly blockedBy: number;
        readonly blocking: number;
      };
      readonly number: number;
      readonly parent: {
        readonly id: string;
        readonly number: number;
        readonly repository: {
          readonly id: string;
          readonly nameWithOwner: string;
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
      readonly repository: {
        readonly id: string;
        readonly isArchived: boolean;
        readonly nameWithOwner: string;
        readonly owner: {
          readonly __typename: string;
          readonly id: string;
          readonly login: string;
        };
      };
      readonly title: string;
      readonly topBlockedBy: {
        readonly nodes: ReadonlyArray<{
          readonly id: string;
          readonly number: number;
          readonly repository: {
            readonly id: string;
            readonly nameWithOwner: string;
          };
          readonly state: IssueState;
          readonly stateReason: IssueStateReason | null | undefined;
          readonly title: string;
          readonly titleHTML: string;
          readonly url: string;
        } | null | undefined> | null | undefined;
        readonly pageInfo: {
          readonly hasNextPage: boolean;
        };
      };
      readonly topBlocking: {
        readonly nodes: ReadonlyArray<{
          readonly id: string;
          readonly number: number;
          readonly repository: {
            readonly id: string;
            readonly nameWithOwner: string;
          };
          readonly state: IssueState;
          readonly stateReason: IssueStateReason | null | undefined;
          readonly title: string;
          readonly titleHTML: string;
          readonly url: string;
        } | null | undefined> | null | undefined;
        readonly pageInfo: {
          readonly hasNextPage: boolean;
        };
      };
      readonly viewerCanUpdateMetadata: boolean | null | undefined;
    } | null | undefined;
    readonly issue: {
      readonly id: string;
      readonly issueDependenciesSummary: {
        readonly blockedBy: number;
        readonly blocking: number;
      };
      readonly parent: {
        readonly id: string;
        readonly number: number;
        readonly repository: {
          readonly id: string;
          readonly nameWithOwner: string;
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
      readonly repository: {
        readonly id: string;
        readonly isArchived: boolean;
        readonly nameWithOwner: string;
        readonly owner: {
          readonly __typename: string;
          readonly id: string;
          readonly login: string;
        };
      };
      readonly topBlockedBy: {
        readonly nodes: ReadonlyArray<{
          readonly id: string;
          readonly number: number;
          readonly repository: {
            readonly id: string;
            readonly nameWithOwner: string;
          };
          readonly state: IssueState;
          readonly stateReason: IssueStateReason | null | undefined;
          readonly title: string;
          readonly titleHTML: string;
          readonly url: string;
        } | null | undefined> | null | undefined;
        readonly pageInfo: {
          readonly hasNextPage: boolean;
        };
      };
      readonly topBlocking: {
        readonly nodes: ReadonlyArray<{
          readonly id: string;
          readonly number: number;
          readonly repository: {
            readonly id: string;
            readonly nameWithOwner: string;
          };
          readonly state: IssueState;
          readonly stateReason: IssueStateReason | null | undefined;
          readonly title: string;
          readonly titleHTML: string;
          readonly url: string;
        } | null | undefined> | null | undefined;
        readonly pageInfo: {
          readonly hasNextPage: boolean;
        };
      };
      readonly viewerCanUpdateMetadata: boolean | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type addBlockedByMutation = {
  rawResponse: addBlockedByMutation$rawResponse;
  response: addBlockedByMutation$data;
  variables: addBlockedByMutation$variables;
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
  "args": null,
  "kind": "FragmentSpread",
  "name": "RelationshipsSectionFragment"
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
  "name": "title",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
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
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    },
    (v3/*: any*/)
  ],
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v6/*: any*/),
    (v3/*: any*/)
  ],
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
},
v13 = {
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
v14 = {
  "alias": null,
  "args": null,
  "concreteType": "Issue",
  "kind": "LinkedField",
  "name": "parent",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v5/*: any*/),
    (v9/*: any*/),
    (v10/*: any*/),
    (v4/*: any*/),
    (v11/*: any*/),
    (v12/*: any*/),
    (v13/*: any*/),
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
    }
  ],
  "storageKey": null
},
v15 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 3
  },
  {
    "kind": "Literal",
    "name": "ranked",
    "value": true
  }
],
v16 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v3/*: any*/),
      (v5/*: any*/),
      (v9/*: any*/),
      (v10/*: any*/),
      (v4/*: any*/),
      (v11/*: any*/),
      (v12/*: any*/),
      (v13/*: any*/)
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
v17 = {
  "alias": "topBlockedBy",
  "args": (v15/*: any*/),
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "blockedBy",
  "plural": false,
  "selections": (v16/*: any*/),
  "storageKey": "blockedBy(first:3,ranked:true)"
},
v18 = {
  "alias": "topBlocking",
  "args": (v15/*: any*/),
  "concreteType": "IssueConnection",
  "kind": "LinkedField",
  "name": "blocking",
  "plural": false,
  "selections": (v16/*: any*/),
  "storageKey": "blocking(first:3,ranked:true)"
},
v19 = {
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
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdateMetadata",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "addBlockedByMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "AddBlockedByPayload",
        "kind": "LinkedField",
        "name": "addBlockedBy",
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
              (v2/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "blockingIssue",
            "plural": false,
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v6/*: any*/)
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
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "addBlockedByMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "AddBlockedByPayload",
        "kind": "LinkedField",
        "name": "addBlockedBy",
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
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v6/*: any*/),
                  (v7/*: any*/),
                  (v3/*: any*/),
                  (v8/*: any*/)
                ],
                "storageKey": null
              },
              (v14/*: any*/),
              (v17/*: any*/),
              (v18/*: any*/),
              (v19/*: any*/),
              (v20/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "blockingIssue",
            "plural": false,
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v6/*: any*/),
                  (v3/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/)
                ],
                "storageKey": null
              },
              (v14/*: any*/),
              (v17/*: any*/),
              (v18/*: any*/),
              (v19/*: any*/),
              (v20/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "7b226e33d51daf610c78cb8637f67eec",
    "metadata": {},
    "name": "addBlockedByMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "8500c41903f52b72cdb6ca44ecb913ec";

export default node;
