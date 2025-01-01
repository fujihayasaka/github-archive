/**
 * @generated SignedSource<<898947d643f558c09eaba3c8280830fd>>
 * @relayHash 9eb457cd6dc49ae9a6c4a27fd73e4050
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 9eb457cd6dc49ae9a6c4a27fd73e4050

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ReactionViewerRelayTestQuery$variables = Record<PropertyKey, never>;
export type ReactionViewerRelayTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
  } | null | undefined;
};
export type ReactionViewerRelayTestQuery = {
  response: ReactionViewerRelayTestQuery$data;
  variables: ReactionViewerRelayTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "reactable-node-id"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
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
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
    "storageKey": null
  }
],
v4 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "ReactionViewerRelayTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "ReactionViewerRelayGroups"
          }
        ],
        "storageKey": "node(id:\"reactable-node-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "ReactionViewerRelayTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "ReactionGroup",
                "kind": "LinkedField",
                "name": "reactionGroups",
                "plural": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "content",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerHasReacted",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": [
                      {
                        "kind": "Literal",
                        "name": "first",
                        "value": 5
                      }
                    ],
                    "concreteType": "ReactorConnection",
                    "kind": "LinkedField",
                    "name": "reactors",
                    "plural": false,
                    "selections": [
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
                        "concreteType": null,
                        "kind": "LinkedField",
                        "name": "nodes",
                        "plural": true,
                        "selections": [
                          (v1/*: any*/),
                          {
                            "kind": "InlineFragment",
                            "selections": (v3/*: any*/),
                            "type": "User",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v3/*: any*/),
                            "type": "Bot",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v3/*: any*/),
                            "type": "Organization",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": (v3/*: any*/),
                            "type": "Mannequin",
                            "abstractKey": null
                          },
                          {
                            "kind": "InlineFragment",
                            "selections": [
                              (v2/*: any*/)
                            ],
                            "type": "Node",
                            "abstractKey": "__isNode"
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "reactors(first:5)"
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "Reactable",
            "abstractKey": "__isReactable"
          }
        ],
        "storageKey": "node(id:\"reactable-node-id\")"
      }
    ]
  },
  "params": {
    "id": "9eb457cd6dc49ae9a6c4a27fd73e4050",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isReactable": (v4/*: any*/),
        "node.__typename": (v4/*: any*/),
        "node.id": (v5/*: any*/),
        "node.reactionGroups": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ReactionGroup"
        },
        "node.reactionGroups.content": {
          "enumValues": [
            "CONFUSED",
            "EYES",
            "HEART",
            "HOORAY",
            "LAUGH",
            "ROCKET",
            "THUMBS_DOWN",
            "THUMBS_UP"
          ],
          "nullable": false,
          "plural": false,
          "type": "ReactionContent"
        },
        "node.reactionGroups.reactors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ReactorConnection"
        },
        "node.reactionGroups.reactors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Reactor"
        },
        "node.reactionGroups.reactors.nodes.__isNode": (v4/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v4/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v5/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v4/*: any*/),
        "node.reactionGroups.reactors.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.reactionGroups.viewerHasReacted": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "ReactionViewerRelayTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "ab75de4147a9c561e8f92cec80bc5c88";

export default node;
