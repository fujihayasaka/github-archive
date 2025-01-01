/**
 * @generated SignedSource<<469122577f54e859916397461fd7d490>>
 * @relayHash 4c9617149e2d4c1d7113fb2daece02e7
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4c9617149e2d4c1d7113fb2daece02e7

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchCurrentRepoTestQuery$variables = Record<PropertyKey, never>;
export type SearchCurrentRepoTestQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"SearchRepositoryFragment">;
  } | null | undefined;
};
export type SearchCurrentRepoTestQuery = {
  response: SearchCurrentRepoTestQuery$data;
  variables: SearchCurrentRepoTestQuery$variables;
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
],
v1 = {
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
    "name": "SearchCurrentRepoTestQuery",
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
            "name": "SearchRepositoryFragment"
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
    "name": "SearchCurrentRepoTestQuery",
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
            "name": "viewerCanPush",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isDisabled",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isLocked",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isArchived",
            "storageKey": null
          },
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
    "id": "4c9617149e2d4c1d7113fb2daece02e7",
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
        "repository.isArchived": (v1/*: any*/),
        "repository.isDisabled": (v1/*: any*/),
        "repository.isInOrganization": (v1/*: any*/),
        "repository.isLocked": (v1/*: any*/),
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
        },
        "repository.viewerCanPush": (v1/*: any*/)
      }
    },
    "name": "SearchCurrentRepoTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "b4cfdfbe8cb1e65369aac5eb0c5c9d67";

export default node;
