/**
 * @generated SignedSource<<2184bccb4986cb6fab9df89e3cd05711>>
 * @relayHash 1b84e165efc796fb19835202ab8b7a12
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 1b84e165efc796fb19835202ab8b7a12

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MentionedEventTestQuery$variables = Record<PropertyKey, never>;
export type MentionedEventTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"MentionedEvent">;
  } | null | undefined;
};
export type MentionedEventTestQuery = {
  response: MentionedEventTestQuery$data;
  variables: MentionedEventTestQuery$variables;
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
v3 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v4 = {
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
    "name": "MentionedEventTestQuery",
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
                "name": "MentionedEvent"
              }
            ],
            "type": "MentionedEvent",
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
    "name": "MentionedEventTestQuery",
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
                "name": "createdAt",
                "storageKey": null
              },
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
              }
            ],
            "type": "MentionedEvent",
            "abstractKey": null
          },
          (v2/*: any*/)
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ]
  },
  "params": {
    "id": "1b84e165efc796fb19835202ab8b7a12",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v3/*: any*/),
        "node.actor": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Actor"
        },
        "node.actor.__isActor": (v3/*: any*/),
        "node.actor.__typename": (v3/*: any*/),
        "node.actor.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "node.actor.id": (v4/*: any*/),
        "node.actor.isCopilot": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "node.actor.login": (v3/*: any*/),
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
        "node.id": (v4/*: any*/)
      }
    },
    "name": "MentionedEventTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "16460a1b716aaf23f622aa0388afb30d";

export default node;
