/**
 * @generated SignedSource<<0c864c28796a78ae68cb75f66b7b7020>>
 * @relayHash c268593ce9cac289824ce453a0caa31d
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c268593ce9cac289824ce453a0caa31d

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneOrderField = "ALPHABETICAL" | "COMPLETED" | "CREATED_AT" | "DUE_DATE" | "ISSUES" | "NUMBER" | "UPDATED_AT" | "%future added value";
export type MilestoneState = "CLOSED" | "OPEN" | "%future added value";
export type OrderDirection = "ASC" | "DESC" | "%future added value";
export type RepositoryMilestoneIndexPageQuery$variables = {
  name: string;
  orderDirection?: OrderDirection | null | undefined;
  orderField?: MilestoneOrderField | null | undefined;
  owner: string;
  state: MilestoneState;
};
export type RepositoryMilestoneIndexPageQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneIndexPageContentInternal">;
  } | null | undefined;
};
export type RepositoryMilestoneIndexPageQuery = {
  response: RepositoryMilestoneIndexPageQuery$data;
  variables: RepositoryMilestoneIndexPageQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
},
v1 = {
  "defaultValue": "DESC",
  "kind": "LocalArgument",
  "name": "orderDirection"
},
v2 = {
  "defaultValue": "CREATED_AT",
  "kind": "LocalArgument",
  "name": "orderField"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v4 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "state"
},
v5 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "name"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v6 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 50
  },
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
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = {
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v9 = [
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
      (v4/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "RepositoryMilestoneIndexPageQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": [
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
            "name": "RepositoryMilestoneIndexPageContentInternal"
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
      (v3/*: any*/),
      (v4/*: any*/),
      (v2/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "RepositoryMilestoneIndexPageQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
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
            "args": (v6/*: any*/),
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
                      (v7/*: any*/),
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
                          (v7/*: any*/)
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
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "__typename",
                        "storageKey": null
                      }
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
            "args": (v6/*: any*/),
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
              (v8/*: any*/),
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
            "selections": (v9/*: any*/),
            "storageKey": "milestones(first:0,states:\"OPEN\")"
          },
          {
            "alias": "closed",
            "args": [
              (v8/*: any*/),
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
            "selections": (v9/*: any*/),
            "storageKey": "milestones(first:0,states:\"CLOSED\")"
          },
          (v7/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "viewerCanPush",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "c268593ce9cac289824ce453a0caa31d",
    "metadata": {},
    "name": "RepositoryMilestoneIndexPageQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "4c594d6cda7c822ae3a150e0d07f1cbf";

export default node;
