/**
 * @generated SignedSource<<09a11e8868c12a506a9f7e0e77039e90>>
 * @relayHash 087730554a5aa0a3e495425d51729a44
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 087730554a5aa0a3e495425d51729a44

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ReactionViewerRelayGroupTestQuery$variables = {
  id: string;
};
export type ReactionViewerRelayGroupTestQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
  } | null | undefined;
};
export type ReactionViewerRelayGroupTestQuery = {
  response: ReactionViewerRelayGroupTestQuery$data;
  variables: ReactionViewerRelayGroupTestQuery$variables;
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
},
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
    "name": "ReactionViewerRelayGroupTestQuery",
    "selections": [
      {
        "alias": "issue",
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
    "name": "ReactionViewerRelayGroupTestQuery",
    "selections": [
      {
        "alias": "issue",
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
            "type": "Issue",
            "abstractKey": null
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "087730554a5aa0a3e495425d51729a44",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "issue.__isReactable": (v6/*: any*/),
        "issue.__typename": (v6/*: any*/),
        "issue.id": (v7/*: any*/),
        "issue.reactionGroups": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ReactionGroup"
        },
        "issue.reactionGroups.content": {
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
        "issue.reactionGroups.reactors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ReactorConnection"
        },
        "issue.reactionGroups.reactors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Reactor"
        },
        "issue.reactionGroups.reactors.nodes.__isNode": (v6/*: any*/),
        "issue.reactionGroups.reactors.nodes.__typename": (v6/*: any*/),
        "issue.reactionGroups.reactors.nodes.id": (v7/*: any*/),
        "issue.reactionGroups.reactors.nodes.isCopilot": (v8/*: any*/),
        "issue.reactionGroups.reactors.nodes.login": (v6/*: any*/),
        "issue.reactionGroups.reactors.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "issue.reactionGroups.viewerHasReacted": (v8/*: any*/)
      }
    },
    "name": "ReactionViewerRelayGroupTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "0c965ee996b87375494de3d57dcbadcf";

export default node;
