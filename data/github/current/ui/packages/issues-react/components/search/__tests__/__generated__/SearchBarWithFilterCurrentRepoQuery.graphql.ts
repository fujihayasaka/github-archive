/**
 * @generated SignedSource<<338e3b9dfd385e1b30729e0a814ed666>>
 * @relayHash 2989c01aabf037fa43528de0ac2a2e90
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2989c01aabf037fa43528de0ac2a2e90

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarWithFilterCurrentRepoQuery$variables = Record<PropertyKey, never>;
export type SearchBarWithFilterCurrentRepoQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchBarRepo">;
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
    "id": "2989c01aabf037fa43528de0ac2a2e90",
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
    "name": "SearchBarWithFilterCurrentRepoQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "1a7822dea1e015b847178a1a049610ca";

export default node;
