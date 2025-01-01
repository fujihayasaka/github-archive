/**
 * @generated SignedSource<<ef03a51e7fbcf5b3eef4184353e278fe>>
 * @relayHash 5bdfc56dc354e1ae97a2c786fd1e9709
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 5bdfc56dc354e1ae97a2c786fd1e9709

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeChangedEventTestQuery$variables = Record<PropertyKey, never>;
export type IssueTypeChangedEventTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypeChangedEvent">;
  } | null | undefined;
};
export type IssueTypeChangedEventTestQuery = {
  response: IssueTypeChangedEventTestQuery$data;
  variables: IssueTypeChangedEventTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "node-id"
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
    "name": "name",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "color",
    "storageKey": null
  },
  (v2/*: any*/)
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
},
v6 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v7 = {
  "enumValues": [
    "BLUE",
    "GRAY",
    "GREEN",
    "ORANGE",
    "PINK",
    "PURPLE",
    "RED",
    "YELLOW"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueTypeChangedEventTestQuery",
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
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueTypeChangedEvent"
              }
            ],
            "type": "IssueTypeChangedEvent",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueTypeChangedEventTestQuery",
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
                "kind": "ScalarField",
                "name": "databaseId",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "actor",
                "plural": false,
                "selections": [
                  (v1/*: any*/),
                  {
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isActor"
                  },
                  {
                    "alias": null,
                    "args": [
                      {
                        "kind": "Literal",
                        "name": "size",
                        "value": 64
                      }
                    ],
                    "kind": "ScalarField",
                    "name": "avatarUrl",
                    "storageKey": "avatarUrl(size:64)"
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "login",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "profileResourcePath",
                    "storageKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
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
                  (v2/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "createdAt",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "issueType",
                "plural": false,
                "selections": (v3/*: any*/),
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "prevIssueType",
                "plural": false,
                "selections": (v3/*: any*/),
                "storageKey": null
              }
            ],
            "type": "IssueTypeChangedEvent",
            "abstractKey": null
          },
          (v2/*: any*/)
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ]
  },
  "params": {
    "id": "5bdfc56dc354e1ae97a2c786fd1e9709",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v4/*: any*/),
        "node.actor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "node.actor.__isActor": (v4/*: any*/),
        "node.actor.__typename": (v4/*: any*/),
        "node.actor.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "node.actor.id": (v5/*: any*/),
        "node.actor.isCopilot": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "node.actor.login": (v4/*: any*/),
        "node.actor.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.createdAt": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "DateTime"
        },
        "node.databaseId": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Int"
        },
        "node.id": (v5/*: any*/),
        "node.issueType": (v6/*: any*/),
        "node.issueType.color": (v7/*: any*/),
        "node.issueType.id": (v5/*: any*/),
        "node.issueType.name": (v4/*: any*/),
        "node.prevIssueType": (v6/*: any*/),
        "node.prevIssueType.color": (v7/*: any*/),
        "node.prevIssueType.id": (v5/*: any*/),
        "node.prevIssueType.name": (v4/*: any*/)
      }
    },
    "name": "IssueTypeChangedEventTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "7b41649b1ac6e2517074b9242aa9c4bb";

export default node;
