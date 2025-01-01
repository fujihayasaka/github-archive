/**
 * @generated SignedSource<<538b9e6c3ee202595ce7f3b1bce0188c>>
 * @relayHash ffc60d4c99d372e22e4b7d230b7d8ba0
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID ffc60d4c99d372e22e4b7d230b7d8ba0

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
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
  "name": "login",
  "storageKey": null
},
v3 = [
  (v2/*: any*/)
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v7 = {
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
                            "selections": [
                              (v2/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "isCopilot",
                                "storageKey": null
                              }
                            ],
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
                              (v4/*: any*/)
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
          },
          (v4/*: any*/)
        ],
        "storageKey": "node(id:\"reactable-node-id\")"
      }
    ]
  },
  "params": {
    "id": "ffc60d4c99d372e22e4b7d230b7d8ba0",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isReactable": (v5/*: any*/),
        "node.__typename": (v5/*: any*/),
        "node.id": (v6/*: any*/),
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
        "node.reactionGroups.reactors.nodes.__isNode": (v5/*: any*/),
        "node.reactionGroups.reactors.nodes.__typename": (v5/*: any*/),
        "node.reactionGroups.reactors.nodes.id": (v6/*: any*/),
        "node.reactionGroups.reactors.nodes.isCopilot": (v7/*: any*/),
        "node.reactionGroups.reactors.nodes.login": (v5/*: any*/),
        "node.reactionGroups.reactors.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.reactionGroups.viewerHasReacted": (v7/*: any*/)
      }
    },
    "name": "ReactionViewerRelayTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "84a1a70cbc53865bc151f18b7ef71fc7";

export default node;
