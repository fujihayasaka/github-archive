/**
 * @generated SignedSource<<2123b1875dffc53a83e7933b7f1e8ff5>>
 * @relayHash a67df37758368d159513db7fa12181c6
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a67df37758368d159513db7fa12181c6

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchCurrentViewTestQuery$variables = Record<PropertyKey, never>;
export type SearchCurrentViewTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchCurrentViewFragment">;
  } | null | undefined;
};
export type SearchCurrentViewTestQuery = {
  response: SearchCurrentViewTestQuery$data;
  variables: SearchCurrentViewTestQuery$variables;
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
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
    "name": "SearchCurrentViewTestQuery",
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
            "name": "SearchCurrentViewFragment"
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
    "name": "SearchCurrentViewTestQuery",
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
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "query",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "scopingRepository",
                "plural": false,
                "selections": [
                  (v3/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v1/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "login",
                        "storageKey": null
                      },
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v2/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "type": "Shortcutable",
            "abstractKey": "__isShortcutable"
          }
        ],
        "storageKey": "node(id:\"node-id\")"
      }
    ]
  },
  "params": {
    "id": "a67df37758368d159513db7fa12181c6",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isShortcutable": (v4/*: any*/),
        "node.__typename": (v4/*: any*/),
        "node.id": (v5/*: any*/),
        "node.name": (v4/*: any*/),
        "node.query": (v4/*: any*/),
        "node.scopingRepository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "node.scopingRepository.id": (v5/*: any*/),
        "node.scopingRepository.name": (v4/*: any*/),
        "node.scopingRepository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "node.scopingRepository.owner.__typename": (v4/*: any*/),
        "node.scopingRepository.owner.id": (v5/*: any*/),
        "node.scopingRepository.owner.login": (v4/*: any*/)
      }
    },
    "name": "SearchCurrentViewTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "52e7014ef536f44eea1d0e77ba0a6800";

export default node;
