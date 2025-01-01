/**
 * @generated SignedSource<<36883f61f621778a2f3124a7e2821ec8>>
 * @relayHash 6c6edeb51718ffa891f269a25152800b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 6c6edeb51718ffa891f269a25152800b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyViewerReactionsStoryQuery$variables = Record<PropertyKey, never>;
export type IssueBodyViewerReactionsStoryQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueBodyViewer" | "IssueBodyViewerReactable">;
  } | null | undefined;
};
export type IssueBodyViewerReactionsStoryQuery = {
  response: IssueBodyViewerReactionsStoryQuery$data;
  variables: IssueBodyViewerReactionsStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "abc"
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
    "name": "IssueBodyViewerReactionsStoryQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v0/*: any*/),
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
                "name": "IssueBodyViewer"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueBodyViewerReactable"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"abc\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueBodyViewerReactionsStoryQuery",
    "selections": [
      {
        "alias": "issue",
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
                "kind": "TypeDiscriminator",
                "abstractKey": "__isComment"
              },
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
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"abc\")"
      }
    ]
  },
  "params": {
    "id": "6c6edeb51718ffa891f269a25152800b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "issue.__isComment": (v5/*: any*/),
        "issue.__isReactable": (v5/*: any*/),
        "issue.__typename": (v5/*: any*/),
        "issue.id": (v6/*: any*/),
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
        "issue.reactionGroups.reactors.nodes.__isNode": (v5/*: any*/),
        "issue.reactionGroups.reactors.nodes.__typename": (v5/*: any*/),
        "issue.reactionGroups.reactors.nodes.id": (v6/*: any*/),
        "issue.reactionGroups.reactors.nodes.isCopilot": (v7/*: any*/),
        "issue.reactionGroups.reactors.nodes.login": (v5/*: any*/),
        "issue.reactionGroups.reactors.totalCount": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "issue.reactionGroups.viewerHasReacted": (v7/*: any*/)
      }
    },
    "name": "IssueBodyViewerReactionsStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "bf27c7d091045679e4c90bc0525089d1";

export default node;
