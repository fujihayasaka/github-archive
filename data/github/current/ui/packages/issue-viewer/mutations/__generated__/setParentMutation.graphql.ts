/**
 * @generated SignedSource<<80d09d80bb7fd85c66c76dd4c4c8cb18>>
 * @relayHash 162f629c3fdd999fb7424cc136a85c90
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 162f629c3fdd999fb7424cc136a85c90

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
export type AddSubIssueInput = {
  clientMutationId?: string | null | undefined;
  issueId: string;
  replaceParent?: boolean | null | undefined;
  subIssueId?: string | null | undefined;
  subIssueUrl?: string | null | undefined;
};
export type setParentMutation$variables = {
  input: AddSubIssueInput;
};
export type setParentMutation$data = {
  readonly addSubIssue: {
    readonly subIssue: {
      readonly " $fragmentSpreads": FragmentRefs<"RelationshipsSectionFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type setParentMutation$rawResponse = {
  readonly addSubIssue: {
    readonly subIssue: {
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
export type setParentMutation = {
  rawResponse: setParentMutation$rawResponse;
  response: setParentMutation$data;
  variables: setParentMutation$variables;
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
  "name": "nameWithOwner",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "titleHTML",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    (v3/*: any*/),
    (v2/*: any*/)
  ],
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
v11 = [
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
v12 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "Issue",
    "kind": "LinkedField",
    "name": "nodes",
    "plural": true,
    "selections": [
      (v2/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/),
      (v7/*: any*/),
      (v8/*: any*/),
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
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "setParentMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "AddSubIssuePayload",
        "kind": "LinkedField",
        "name": "addSubIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "RelationshipsSectionFragment"
              }
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
    "name": "setParentMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "AddSubIssuePayload",
        "kind": "LinkedField",
        "name": "addSubIssue",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "subIssue",
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
                  {
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
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isArchived",
                    "storageKey": null
                  }
                ],
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
                  (v4/*: any*/),
                  (v5/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
                  (v9/*: any*/),
                  (v10/*: any*/),
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
              {
                "alias": "topBlockedBy",
                "args": (v11/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blockedBy",
                "plural": false,
                "selections": (v12/*: any*/),
                "storageKey": "blockedBy(first:3,ranked:true)"
              },
              {
                "alias": "topBlocking",
                "args": (v11/*: any*/),
                "concreteType": "IssueConnection",
                "kind": "LinkedField",
                "name": "blocking",
                "plural": false,
                "selections": (v12/*: any*/),
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
    "id": "162f629c3fdd999fb7424cc136a85c90",
    "metadata": {},
    "name": "setParentMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "d7ae6b6f869509e0cb75ae50298a2db5";

export default node;
