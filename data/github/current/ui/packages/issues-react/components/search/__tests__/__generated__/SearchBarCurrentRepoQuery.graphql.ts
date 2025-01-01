/**
 * @generated SignedSource<<88727d903efbf953b1069adf1fb40c63>>
 * @relayHash e3d40a8293b4d33ea38fbbee6d930130
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID e3d40a8293b4d33ea38fbbee6d930130

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarCurrentRepoQuery$variables = Record<PropertyKey, never>;
export type SearchBarCurrentRepoQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchBarRepo">;
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
            "name": "SearchBarRepo"
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
            "name": "isInOrganization",
            "storageKey": null
          },
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
            "name": "nameWithOwner",
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
    "id": "e3d40a8293b4d33ea38fbbee6d930130",
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
        "repository.isInOrganization": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        },
        "repository.isOwnerEnterpriseManaged": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        },
        "repository.nameWithOwner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        }
      }
    },
    "name": "SearchBarCurrentRepoQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "f72257bb4a144b14ad596d0821586966";

export default node;
