/**
 * @generated SignedSource<<44c32a0236d928f7c1e710e192f88daa>>
 * @relayHash 7c025f24b352da549e1d6ac5c097b376
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7c025f24b352da549e1d6ac5c097b376

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneOrderField = "ALPHABETICAL" | "COMPLETED" | "CREATED_AT" | "DUE_DATE" | "ISSUES" | "NUMBER" | "UPDATED_AT" | "%future added value";
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
export type OrderDirection = "ASC" | "DESC" | "%future added value";
export type MilestoneListQuery$variables = {
  cursor?: string | null | undefined;
  first: number;
  id: string;
  orderDirection?: OrderDirection | null | undefined;
  orderField?: MilestoneOrderField | null | undefined;
  state: MilestoneState;
};
export type MilestoneListQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneList">;
  } | null | undefined;
};
export type MilestoneListQuery = {
  response: MilestoneListQuery$data;
  variables: MilestoneListQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "cursor"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "first"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "id"
},
v3 = {
  "defaultValue": "DESC",
  "kind": "LocalArgument",
  "name": "orderDirection"
},
v4 = {
  "defaultValue": "CREATED_AT",
  "kind": "LocalArgument",
  "name": "orderField"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "state"
},
v6 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v7 = {
  "kind": "Variable",
  "name": "first",
  "variableName": "first"
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v10 = [
  {
    "kind": "Variable",
    "name": "after",
    "variableName": "cursor"
  },
  (v7/*: any*/),
  {
    "fields": [
      {
        "kind": "Variable",
        "name": "direction",
        "variableName": "orderDirection"
      },
      {
        "kind": "Variable",
        "name": "field",
        "variableName": "orderField"
      }
    ],
    "kind": "ObjectValue",
    "name": "orderBy"
  },
  {
    "items": [
      {
        "kind": "Variable",
        "name": "states.0",
        "variableName": "state"
      }
    ],
    "kind": "ListValue",
    "name": "states"
  }
],
v11 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v12 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "MilestoneListQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "cursor",
                "variableName": "cursor"
              },
              (v7/*: any*/),
              {
                "kind": "Variable",
                "name": "orderDirection",
                "variableName": "orderDirection"
              },
              {
                "kind": "Variable",
                "name": "orderField",
                "variableName": "orderField"
              },
              {
                "kind": "Variable",
                "name": "state",
                "variableName": "state"
              }
            ],
            "kind": "FragmentSpread",
            "name": "MilestoneList"
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
      (v0/*: any*/),
      (v1/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Operation",
    "name": "MilestoneListQuery",
    "selections": [
      {
        "alias": null,
        "args": (v6/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v8/*: any*/),
          (v9/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "nameWithOwner",
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v10/*: any*/),
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "MilestoneEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "Milestone",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v9/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "description",
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
                            "name": "url",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "state",
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
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "progressPercentage",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "openIssueCount",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "closedIssueCount",
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "dueOn",
                            "storageKey": null
                          },
                          (v8/*: any*/)
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
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v10/*: any*/),
                "filters": [
                  "states",
                  "orderBy"
                ],
                "handle": "connection",
                "key": "MilestoneList_milestones",
                "kind": "LinkedHandle",
                "name": "milestones"
              },
              {
                "alias": "open",
                "args": [
                  (v11/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "states",
                    "value": "OPEN"
                  }
                ],
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": (v12/*: any*/),
                "storageKey": "milestones(first:0,states:\"OPEN\")"
              },
              {
                "alias": "closed",
                "args": [
                  (v11/*: any*/),
                  {
                    "kind": "Literal",
                    "name": "states",
                    "value": "CLOSED"
                  }
                ],
                "concreteType": "MilestoneConnection",
                "kind": "LinkedField",
                "name": "milestones",
                "plural": false,
                "selections": (v12/*: any*/),
                "storageKey": "milestones(first:0,states:\"CLOSED\")"
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "7c025f24b352da549e1d6ac5c097b376",
    "metadata": {},
    "name": "MilestoneListQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "3db42140a58f5e3d4d9a2b592ed1efb7";

export default node;
