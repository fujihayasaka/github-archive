/**
 * @generated SignedSource<<f4c368c8b988dee09c31abcb10904749>>
 * @relayHash fc2ffc0bc79753a450cebbc5804a6c88
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fc2ffc0bc79753a450cebbc5804a6c88

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PaginatedOrganizationPickerFetchedByIDQuery$variables = {
  ids: ReadonlyArray<string>;
};
export type PaginatedOrganizationPickerFetchedByIDQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly __typename: string;
    readonly " $fragmentSpreads": FragmentRefs<"OrganizationPickerFragment">;
  } | null | undefined>;
};
export type PaginatedOrganizationPickerFetchedByIDQuery = {
  response: PaginatedOrganizationPickerFetchedByIDQuery$data;
  variables: PaginatedOrganizationPickerFetchedByIDQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "ids"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "ids"
  }
],
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
  "name": "login",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "avatarUrl",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "PaginatedOrganizationPickerFetchedByIDQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "kind": "InlineDataFragmentSpread",
            "name": "OrganizationPickerFragment",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/)
                ],
                "type": "Organization",
                "abstractKey": null
              }
            ],
            "args": null,
            "argumentDefinitions": []
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "PaginatedOrganizationPickerFetchedByIDQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v5/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/)
            ],
            "type": "Organization",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "fc2ffc0bc79753a450cebbc5804a6c88",
    "metadata": {},
    "name": "PaginatedOrganizationPickerFetchedByIDQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "2fd0560c06590a9e8cbbdf61cdfac313";

export default node;
