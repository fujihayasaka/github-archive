/**
 * @generated SignedSource<<286ec690533302677e50c5532fd73e94>>
 * @relayHash c90d161d6aa973bbbba7ead55d818d27
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c90d161d6aa973bbbba7ead55d818d27

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryLabelsInternalStoryQuery$variables = Record<PropertyKey, never>;
export type RepositoryLabelsInternalStoryQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"RepositoryLabelsInternal">;
  } | null | undefined;
};
export type RepositoryLabelsInternalStoryQuery = {
  response: RepositoryLabelsInternalStoryQuery$data;
  variables: RepositoryLabelsInternalStoryQuery$variables;
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
v1 = {
  "kind": "Literal",
  "name": "skip",
  "value": 0
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 30
  },
  {
    "fields": [
      {
        "kind": "Literal",
        "name": "direction",
        "value": "ASC"
      },
      {
        "kind": "Literal",
        "name": "field",
        "value": "NAME"
      }
    ],
    "kind": "ObjectValue",
    "name": "orderBy"
  },
  (v1/*: any*/)
],
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v7 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "RepositoryLabelsInternalStoryQuery",
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
              (v1/*: any*/)
            ],
            "kind": "FragmentSpread",
            "name": "RepositoryLabelsInternal"
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
    "name": "RepositoryLabelsInternalStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "nameWithOwner",
            "storageKey": null
          },
          {
            "alias": null,
            "args": (v3/*: any*/),
            "concreteType": "LabelConnection",
            "kind": "LinkedField",
            "name": "labels",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "LabelEdge",
                "kind": "LinkedField",
                "name": "edges",
                "plural": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Label",
                    "kind": "LinkedField",
                    "name": "node",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "name",
                        "storageKey": null
                      },
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
                "kind": "ScalarField",
                "name": "totalCount",
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
            "storageKey": "labels(first:30,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"},skip:0)"
          },
          {
            "alias": null,
            "args": (v3/*: any*/),
            "filters": [
              "query",
              "orderBy",
              "skip"
            ],
            "handle": "connection",
            "key": "LabelList_labels",
            "kind": "LinkedHandle",
            "name": "labels"
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isWritable",
            "storageKey": null
          },
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
    "id": "c90d161d6aa973bbbba7ead55d818d27",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v4/*: any*/),
        "repository.isWritable": (v5/*: any*/),
        "repository.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "repository.labels.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LabelEdge"
        },
        "repository.labels.edges.cursor": (v6/*: any*/),
        "repository.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "repository.labels.edges.node.__typename": (v6/*: any*/),
        "repository.labels.edges.node.color": (v6/*: any*/),
        "repository.labels.edges.node.description": (v7/*: any*/),
        "repository.labels.edges.node.id": (v4/*: any*/),
        "repository.labels.edges.node.name": (v6/*: any*/),
        "repository.labels.edges.node.nameHTML": (v6/*: any*/),
        "repository.labels.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "repository.labels.pageInfo.endCursor": (v7/*: any*/),
        "repository.labels.pageInfo.hasNextPage": (v5/*: any*/),
        "repository.labels.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "repository.nameWithOwner": (v6/*: any*/),
        "repository.viewerCanPush": (v5/*: any*/)
      }
    },
    "name": "RepositoryLabelsInternalStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e97d1159b4d6bb714ddf6438c1844a3e";

export default node;
