/**
 * @generated SignedSource<<45aca2a42796d006ac073438498074da>>
 * @relayHash 41feeeb7ecaeadd65453054469f1c3d8
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 41feeeb7ecaeadd65453054469f1c3d8

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AddToProjectsActionTestQuery$variables = {
  ids: ReadonlyArray<string>;
};
export type AddToProjectsActionTestQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly id?: string;
    readonly projectItemsNext?: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly id: string;
          readonly project: {
            readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
          };
        } | null | undefined;
      } | null | undefined> | null | undefined;
    } | null | undefined;
  } | null | undefined>;
};
export type AddToProjectsActionTestQuery = {
  response: AddToProjectsActionTestQuery$data;
  variables: AddToProjectsActionTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "ids"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "ids"
  }
],
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
    "value": 10
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v5 = [
  (v2/*: any*/),
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
    "name": "closed",
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
    "name": "url",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "viewerCanUpdate",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "hasReachedItemsLimit",
    "storageKey": null
  },
  (v4/*: any*/)
],
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
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
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "AddToProjectsActionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "ProjectV2ItemConnection",
                "kind": "LinkedField",
                "name": "projectItemsNext",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "ProjectV2ItemEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "ProjectV2Item",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "ProjectV2",
                            "kind": "LinkedField",
                            "name": "project",
                            "plural": false,
                            "selections": [
                              {
                                "kind": "InlineDataFragmentSpread",
                                "name": "ProjectPickerProject",
                                "selections": (v5/*: any*/),
                                "args": null,
                                "argumentDefinitions": []
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "projectItemsNext(first:10)"
              }
            ],
            "type": "Issue",
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
    "name": "AddToProjectsActionTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v4/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "ProjectV2ItemConnection",
                "kind": "LinkedField",
                "name": "projectItemsNext",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "ProjectV2ItemEdge",
                    "kind": "LinkedField",
                    "name": "edges",
                    "plural": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "ProjectV2Item",
                        "kind": "LinkedField",
                        "name": "node",
                        "plural": false,
                        "selections": [
                          (v2/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "ProjectV2",
                            "kind": "LinkedField",
                            "name": "project",
                            "plural": false,
                            "selections": (v5/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "projectItemsNext(first:10)"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "41feeeb7ecaeadd65453054469f1c3d8",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "nodes": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "Node"
        },
        "nodes.__typename": (v6/*: any*/),
        "nodes.id": (v7/*: any*/),
        "nodes.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "nodes.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "nodes.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "nodes.projectItemsNext.edges.node.id": (v7/*: any*/),
        "nodes.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "nodes.projectItemsNext.edges.node.project.__typename": (v6/*: any*/),
        "nodes.projectItemsNext.edges.node.project.closed": (v8/*: any*/),
        "nodes.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v8/*: any*/),
        "nodes.projectItemsNext.edges.node.project.id": (v7/*: any*/),
        "nodes.projectItemsNext.edges.node.project.number": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "nodes.projectItemsNext.edges.node.project.title": (v6/*: any*/),
        "nodes.projectItemsNext.edges.node.project.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "nodes.projectItemsNext.edges.node.project.viewerCanUpdate": (v8/*: any*/)
      }
    },
    "name": "AddToProjectsActionTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "d73e6d0f86a62ebb339578407442e3af";

export default node;
