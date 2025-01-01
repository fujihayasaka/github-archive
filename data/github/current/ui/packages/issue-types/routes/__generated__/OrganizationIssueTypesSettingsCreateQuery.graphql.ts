/**
 * @generated SignedSource<<eacebbf8116831277becba2928d64d4f>>
 * @relayHash a9bda7b4294ce433da2875a022394d20
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID a9bda7b4294ce433da2875a022394d20

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OrganizationIssueTypesSettingsCreateQuery$variables = {
  organization_id: string;
};
export type OrganizationIssueTypesSettingsCreateQuery$data = {
  readonly organization: {
    readonly id: string;
    readonly issueTypes: {
      readonly " $fragmentSpreads": FragmentRefs<"OrganizationIssueTypesSettingsCreateIssueTypes">;
    } | null | undefined;
    readonly login: string;
  } | null | undefined;
};
export type OrganizationIssueTypesSettingsCreateQuery = {
  response: OrganizationIssueTypesSettingsCreateQuery$data;
  variables: OrganizationIssueTypesSettingsCreateQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "organization_id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "login",
    "variableName": "organization_id"
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
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "OrganizationIssueTypesSettingsCreateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Organization",
        "kind": "LinkedField",
        "name": "organization",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueTypeConnection",
            "kind": "LinkedField",
            "name": "issueTypes",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "OrganizationIssueTypesSettingsCreateIssueTypes"
              }
            ],
            "storageKey": null
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
    "name": "OrganizationIssueTypesSettingsCreateQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Organization",
        "kind": "LinkedField",
        "name": "organization",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueTypeConnection",
            "kind": "LinkedField",
            "name": "issueTypes",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "totalCount",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueTypeEdge",
                "kind": "LinkedField",
                "name": "edges",
                "plural": true,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "IssueType",
                    "kind": "LinkedField",
                    "name": "node",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "name",
                        "storageKey": null
                      },
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "a9bda7b4294ce433da2875a022394d20",
    "metadata": {},
    "name": "OrganizationIssueTypesSettingsCreateQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "eebfe7013fceb3b93eaf983618512faa";

export default node;
