/**
 * @generated SignedSource<<7c213b376052456cb027f0d29dac6543>>
 * @relayHash 2b187690600d6d755b179e8d9892d3c8
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 2b187690600d6d755b179e8d9892d3c8

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueCreatePageTestQuery$variables = Record<PropertyKey, never>;
export type IssueCreatePageTestQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueCreatePage">;
  } | null | undefined;
};
export type IssueCreatePageTestQuery = {
  response: IssueCreatePageTestQuery$data;
  variables: IssueCreatePageTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "repo"
  },
  {
    "kind": "Literal",
    "name": "owner",
    "value": "owner"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v3 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v4 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueCreatePageTestQuery",
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
            "name": "IssueCreatePage"
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueCreatePageTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "name",
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
            "concreteType": null,
            "kind": "LinkedField",
            "name": "owner",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "__typename",
                "storageKey": null
              },
              (v2/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "login",
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
              },
              (v1/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isPrivate",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "visibility",
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
            "name": "hasIssuesEnabled",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "slashCommandsEnabled",
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
            "concreteType": "IssueCreationPermissions",
            "kind": "LinkedField",
            "name": "viewerIssueCreationPermissions",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "labelable",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "milestoneable",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "assignable",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "triageable",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "typeable",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "securityPolicyUrl",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "contributingFileUrl",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "codeOfConductFileUrl",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "shortDescriptionHTML",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "RepositoryPlanFeatures",
            "kind": "LinkedField",
            "name": "planFeatures",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "maximumAssignees",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "hasAnyTemplates",
            "storageKey": null
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "2b187690600d6d755b179e8d9892d3c8",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.codeOfConductFileUrl": (v3/*: any*/),
        "repository.contributingFileUrl": (v3/*: any*/),
        "repository.databaseId": (v4/*: any*/),
        "repository.hasAnyTemplates": (v5/*: any*/),
        "repository.hasIssuesEnabled": (v5/*: any*/),
        "repository.id": (v6/*: any*/),
        "repository.isArchived": (v5/*: any*/),
        "repository.isInOrganization": (v5/*: any*/),
        "repository.isPrivate": (v5/*: any*/),
        "repository.name": (v7/*: any*/),
        "repository.nameWithOwner": (v7/*: any*/),
        "repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.owner.__typename": (v7/*: any*/),
        "repository.owner.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "repository.owner.databaseId": (v4/*: any*/),
        "repository.owner.id": (v6/*: any*/),
        "repository.owner.login": (v7/*: any*/),
        "repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "repository.planFeatures.maximumAssignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "repository.securityPolicyUrl": (v3/*: any*/),
        "repository.shortDescriptionHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "repository.slashCommandsEnabled": (v5/*: any*/),
        "repository.viewerCanPush": (v5/*: any*/),
        "repository.viewerIssueCreationPermissions": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueCreationPermissions"
        },
        "repository.viewerIssueCreationPermissions.assignable": (v5/*: any*/),
        "repository.viewerIssueCreationPermissions.labelable": (v5/*: any*/),
        "repository.viewerIssueCreationPermissions.milestoneable": (v5/*: any*/),
        "repository.viewerIssueCreationPermissions.triageable": (v5/*: any*/),
        "repository.viewerIssueCreationPermissions.typeable": (v5/*: any*/),
        "repository.visibility": {
          "enumValues": [
            "INTERNAL",
            "PRIVATE",
            "PUBLIC"
          ],
          "nullable": false,
          "plural": false,
          "type": "RepositoryVisibility"
        }
      }
    },
    "name": "IssueCreatePageTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "4ddc873216683396b50d2b609c225848";

export default node;
