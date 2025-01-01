/**
 * @generated SignedSource<<f07e5796ae13c48e6b91b6803a907567>>
 * @relayHash c958dda1c7647a2b2764a24d9417ef29
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c958dda1c7647a2b2764a24d9417ef29

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OrgUserPickerQuery$variables = {
  orgName: string;
};
export type OrgUserPickerQuery$data = {
  readonly organization: {
    readonly membersWithRole: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"UserPickerUserFragment">;
      } | null | undefined> | null | undefined;
    };
  } | null | undefined;
};
export type OrgUserPickerQuery = {
  response: OrgUserPickerQuery$data;
  variables: OrgUserPickerQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "orgName"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "login",
    "variableName": "orgName"
  }
],
v2 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = [
  (v3/*: any*/),
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
    "name": "name",
    "storageKey": null
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
  }
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "OrgUserPickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Organization",
        "kind": "LinkedField",
        "name": "organization",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v2/*: any*/),
            "concreteType": "OrganizationMemberConnection",
            "kind": "LinkedField",
            "name": "membersWithRole",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "User",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": [
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "UserPickerUserFragment",
                    "selections": (v4/*: any*/),
                    "args": null,
                    "argumentDefinitions": []
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": "membersWithRole(first:10)"
          }
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
    "name": "OrgUserPickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Organization",
        "kind": "LinkedField",
        "name": "organization",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v2/*: any*/),
            "concreteType": "OrganizationMemberConnection",
            "kind": "LinkedField",
            "name": "membersWithRole",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "User",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": (v4/*: any*/),
                "storageKey": null
              }
            ],
            "storageKey": "membersWithRole(first:10)"
          },
          (v3/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "c958dda1c7647a2b2764a24d9417ef29",
    "metadata": {},
    "name": "OrgUserPickerQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "98568549ca1346b26f2b3e89b3941e33";

export default node;
