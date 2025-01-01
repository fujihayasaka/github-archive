/**
 * @generated SignedSource<<1d6dca5b0103e6ee0cf5809f845eef72>>
 * @relayHash d4cfb4471d9537e3b97209288b12272b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d4cfb4471d9537e3b97209288b12272b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarWithFilterQuery$variables = Record<PropertyKey, never>;
export type SearchBarWithFilterQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchBarCurrentViewFragment">;
  } | null | undefined;
};
export type SearchBarWithFilterQuery = {
  response: SearchBarWithFilterQuery$data;
  variables: SearchBarWithFilterQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "SSC_asdkasd"
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
    "name": "SearchBarWithFilterQuery",
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
            "name": "SearchBarCurrentViewFragment"
          }
        ],
        "storageKey": "node(id:\"SSC_asdkasd\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "SearchBarWithFilterQuery",
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
        "storageKey": "node(id:\"SSC_asdkasd\")"
      }
    ]
  },
  "params": {
    "id": "d4cfb4471d9537e3b97209288b12272b",
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
    "name": "SearchBarWithFilterQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a9468cbced473523adbb9356fe6d5f4c";

export default node;
