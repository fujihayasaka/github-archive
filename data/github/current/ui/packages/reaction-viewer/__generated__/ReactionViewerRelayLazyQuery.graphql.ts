/**
 * @generated SignedSource<<08f1544882676dbf510f30a538ab3a68>>
 * @relayHash 4ad1541bb8051d5b7a55a10bbdf54731
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4ad1541bb8051d5b7a55a10bbdf54731

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ReactionViewerRelayLazyQuery$variables = {
  id: string;
};
export type ReactionViewerRelayLazyQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
  } | null | undefined;
};
export type ReactionViewerRelayLazyQuery = {
  response: ReactionViewerRelayLazyQuery$data;
  variables: ReactionViewerRelayLazyQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v4 = [
  (v3/*: any*/)
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ReactionViewerRelayLazyQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "ReactionViewerRelayGroups"
              }
            ],
            "type": "Comment",
            "abstractKey": "__isComment"
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
    "name": "ReactionViewerRelayLazyQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
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
                              (v2/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": (v4/*: any*/),
                                "type": "User",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v3/*: any*/),
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
                                "selections": (v4/*: any*/),
                                "type": "Organization",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": (v4/*: any*/),
                                "type": "Mannequin",
                                "abstractKey": null
                              },
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v5/*: any*/)
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
            "type": "Comment",
            "abstractKey": "__isComment"
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "4ad1541bb8051d5b7a55a10bbdf54731",
    "metadata": {},
    "name": "ReactionViewerRelayLazyQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "37ec1495c4c7ace448e859305895ad0e";

export default node;
