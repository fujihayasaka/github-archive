/**
 * @generated SignedSource<<e6d845e4b3095ad6aab58825608624b4>>
 * @relayHash 8718d8f83b5f0832f937d7643f4a56ac
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 8718d8f83b5f0832f937d7643f4a56ac

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SearchBarWithFilterCurrentRepoQuery$variables = Record<PropertyKey, never>;
export type SearchBarWithFilterCurrentRepoQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchBarActionsRepositoryFragment">;
  } | null | undefined;
};
export type SearchBarWithFilterCurrentRepoQuery = {
  response: SearchBarWithFilterCurrentRepoQuery$data;
  variables: SearchBarWithFilterCurrentRepoQuery$variables;
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
    "name": "SearchBarWithFilterCurrentRepoQuery",
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
    "name": "SearchBarWithFilterCurrentRepoQuery",
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
    "id": "8718d8f83b5f0832f937d7643f4a56ac",
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
    "name": "SearchBarWithFilterCurrentRepoQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e451ad6adce6c87ff2f4d8e1265b3fa9";

export default node;
