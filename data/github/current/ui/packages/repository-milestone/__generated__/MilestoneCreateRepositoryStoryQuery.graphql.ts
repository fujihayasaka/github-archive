/**
 * @generated SignedSource<<0eb3ea3622dcfc22ae2ccbad772cc4b9>>
 * @relayHash 7683b40bcc1866cf3bfab8c2ba201310
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7683b40bcc1866cf3bfab8c2ba201310

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneCreateRepositoryStoryQuery$variables = Record<PropertyKey, never>;
export type MilestoneCreateRepositoryStoryQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneCreateFormRepositoryQuery">;
  } | null | undefined;
};
export type MilestoneCreateRepositoryStoryQuery = {
  response: MilestoneCreateRepositoryStoryQuery$data;
  variables: MilestoneCreateRepositoryStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "name"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
];
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "MilestoneCreateRepositoryStoryQuery",
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
            "name": "MilestoneCreateFormRepositoryQuery"
          }
        ],
        "storageKey": "repository(name:\"name\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "MilestoneCreateRepositoryStoryQuery",
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
            "name": "nameWithOwner",
            "storageKey": null
          },
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
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": "repository(name:\"name\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "7683b40bcc1866cf3bfab8c2ba201310",
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
        "repository.nameWithOwner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "String"
        },
        "repository.viewerCanPush": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "MilestoneCreateRepositoryStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "12fb54740280bd2bc8c2595c87f214db";

export default node;
