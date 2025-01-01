/**
 * @generated SignedSource<<5f54c5e30954deb2191df6a034c8765c>>
 * @relayHash 1f195394989474913c835e7eeedaa88c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 1f195394989474913c835e7eeedaa88c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestonesInternalStoryQuery$variables = Record<PropertyKey, never>;
export type RepositoryMilestonesInternalStoryQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestonesInternal">;
  } | null | undefined;
};
export type RepositoryMilestonesInternalStoryQuery = {
  response: RepositoryMilestonesInternalStoryQuery$data;
  variables: RepositoryMilestonesInternalStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "name"
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
    "name": "first",
    "value": 50
  },
  {
    "fields": [
      {
        "kind": "Literal",
        "name": "direction",
        "value": "DESC"
      },
      {
        "kind": "Literal",
        "name": "field",
        "value": "CREATED_AT"
      }
    ],
    "kind": "ObjectValue",
    "name": "orderBy"
  },
  {
    "items": [
      {
        "kind": "Literal",
        "name": "states.0",
        "value": "OPEN"
      }
    ],
    "kind": "ListValue",
    "name": "states"
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
  "kind": "Literal",
  "name": "first",
  "value": 0
},
v4 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "totalCount",
    "storageKey": null
  }
],
v5 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "MilestoneConnection"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v9 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "RepositoryMilestonesInternalStoryQuery",
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
            "args": [
              {
                "kind": "Literal",
                "name": "state",
                "value": "OPEN"
              }
            ],
            "kind": "FragmentSpread",
            "name": "RepositoryMilestonesInternal"
          }
        ],
        "storageKey": "repository(name:\"name\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "RepositoryMilestonesInternalStoryQuery",
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
            "name": "nameWithOwner",
            "storageKey": null
          },
          {
            "alias": null,
            "args": (v1/*: any*/),
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
                      (v2/*: any*/),
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
                          (v2/*: any*/)
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
            "storageKey": "milestones(first:50,orderBy:{\"direction\":\"DESC\",\"field\":\"CREATED_AT\"},states:[\"OPEN\"])"
          },
          {
            "alias": null,
            "args": (v1/*: any*/),
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
              (v3/*: any*/),
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
            "selections": (v4/*: any*/),
            "storageKey": "milestones(first:0,states:\"OPEN\")"
          },
          {
            "alias": "closed",
            "args": [
              (v3/*: any*/),
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
            "selections": (v4/*: any*/),
            "storageKey": "milestones(first:0,states:\"CLOSED\")"
          },
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "viewerCanPush",
            "storageKey": null
          }
        ],
        "storageKey": "repository(name:\"name\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "1f195394989474913c835e7eeedaa88c",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.closed": (v5/*: any*/),
        "repository.closed.totalCount": (v6/*: any*/),
        "repository.id": (v7/*: any*/),
        "repository.milestones": (v5/*: any*/),
        "repository.milestones.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "MilestoneEdge"
        },
        "repository.milestones.edges.cursor": (v8/*: any*/),
        "repository.milestones.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "repository.milestones.edges.node.__typename": (v8/*: any*/),
        "repository.milestones.edges.node.closedIssueCount": (v6/*: any*/),
        "repository.milestones.edges.node.description": (v9/*: any*/),
        "repository.milestones.edges.node.dueOn": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "DateTime"
        },
        "repository.milestones.edges.node.id": (v7/*: any*/),
        "repository.milestones.edges.node.openIssueCount": (v6/*: any*/),
        "repository.milestones.edges.node.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "repository.milestones.edges.node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "repository.milestones.edges.node.repository.id": (v7/*: any*/),
        "repository.milestones.edges.node.state": {
          "enumValues": [
            "CLOSED",
            "OPEN"
          ],
          "nullable": false,
          "plural": false,
          "type": "MilestoneState"
        },
        "repository.milestones.edges.node.title": (v8/*: any*/),
        "repository.milestones.edges.node.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "repository.milestones.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "repository.milestones.pageInfo.endCursor": (v9/*: any*/),
        "repository.milestones.pageInfo.hasNextPage": (v10/*: any*/),
        "repository.nameWithOwner": (v8/*: any*/),
        "repository.open": (v5/*: any*/),
        "repository.open.totalCount": (v6/*: any*/),
        "repository.viewerCanPush": (v10/*: any*/)
      }
    },
    "name": "RepositoryMilestonesInternalStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "2438df5d881f4aab24ab7693ff875420";

export default node;
