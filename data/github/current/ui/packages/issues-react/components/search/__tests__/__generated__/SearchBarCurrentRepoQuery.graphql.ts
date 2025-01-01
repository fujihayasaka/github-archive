/**
 * @generated SignedSource<<7922bc9a5230f25e46a94af5b3b91bd9>>
 * @relayHash 05540a667171f13396a2162e124d869e
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 05540a667171f13396a2162e124d869e

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarCurrentRepoQuery$variables = Record<PropertyKey, never>;
export type SearchBarCurrentRepoQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment">;
  } | null | undefined;
};
export type SearchBarCurrentRepoQuery = {
  response: SearchBarCurrentRepoQuery$data;
  variables: SearchBarCurrentRepoQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "test-repo-name"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "test-repo-owner"
  }
];
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "SearchBarCurrentRepoQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "SearchBarActionsRepositoryFragment"
          }
        ],
        "storageKey": "repository(name:\"test-repo-name\",owner:\"test-repo-owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "SearchBarCurrentRepoQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isOwnerEnterpriseManaged",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": "repository(name:\"test-repo-name\",owner:\"test-repo-owner\")"
      }
    ]
  },
  "params": {
    "id": "05540a667171f13396a2162e124d869e",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "repository.isOwnerEnterpriseManaged": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "SearchBarCurrentRepoQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a9b2f586bd69a78b5abfd50d50af7837";

export default node;
