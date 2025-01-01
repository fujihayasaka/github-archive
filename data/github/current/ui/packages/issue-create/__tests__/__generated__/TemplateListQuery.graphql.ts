/**
 * @generated SignedSource<<f0b0e79dca6c400ddce944f8a9b8c3d2>>
 * @relayHash 68deb26534568fc36a889060a8fd2a23
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 68deb26534568fc36a889060a8fd2a23

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplateListQuery$variables = Record<PropertyKey, never>;
export type TemplateListQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"TemplateList">;
  } | null | undefined;
};
export type TemplateListQuery = {
  response: TemplateListQuery$data;
  variables: TemplateListQuery$variables;
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
  "name": "__typename",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "filename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "about",
  "storageKey": null
},
v5 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v7 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v8 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "TemplateListQuery",
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
            "name": "TemplateList"
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
    "name": "TemplateListQuery",
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
            "name": "id",
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
            "concreteType": "IssueForm",
            "kind": "LinkedField",
            "name": "issueForms",
            "plural": true,
            "selections": [
              (v1/*: any*/),
              (v2/*: any*/),
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "description",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueTemplate",
            "kind": "LinkedField",
            "name": "issueTemplates",
            "plural": true,
            "selections": [
              (v1/*: any*/),
              (v2/*: any*/),
              (v3/*: any*/),
              (v4/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isBlankIssuesEnabled",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isSecurityPolicyEnabled",
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
            "concreteType": "RepositoryContactLink",
            "kind": "LinkedField",
            "name": "contactLinks",
            "plural": true,
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "url",
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
                "name": "typeable",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "triageable",
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "templateTreeUrl",
            "storageKey": null
          }
        ],
        "storageKey": "repository(name:\"repo\",owner:\"owner\")"
      }
    ]
  },
  "params": {
    "id": "68deb26534568fc36a889060a8fd2a23",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.contactLinks": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "RepositoryContactLink"
        },
        "repository.contactLinks.about": (v5/*: any*/),
        "repository.contactLinks.name": (v5/*: any*/),
        "repository.contactLinks.url": (v6/*: any*/),
        "repository.hasAnyTemplates": (v7/*: any*/),
        "repository.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "repository.isBlankIssuesEnabled": (v7/*: any*/),
        "repository.isSecurityPolicyEnabled": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        },
        "repository.issueForms": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueForm"
        },
        "repository.issueForms.__typename": (v5/*: any*/),
        "repository.issueForms.description": (v8/*: any*/),
        "repository.issueForms.filename": (v5/*: any*/),
        "repository.issueForms.name": (v5/*: any*/),
        "repository.issueTemplates": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTemplate"
        },
        "repository.issueTemplates.__typename": (v5/*: any*/),
        "repository.issueTemplates.about": (v8/*: any*/),
        "repository.issueTemplates.filename": (v5/*: any*/),
        "repository.issueTemplates.name": (v5/*: any*/),
        "repository.nameWithOwner": (v5/*: any*/),
        "repository.securityPolicyUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "repository.templateTreeUrl": (v6/*: any*/),
        "repository.viewerCanPush": (v7/*: any*/),
        "repository.viewerIssueCreationPermissions": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueCreationPermissions"
        },
        "repository.viewerIssueCreationPermissions.triageable": (v7/*: any*/),
        "repository.viewerIssueCreationPermissions.typeable": (v7/*: any*/)
      }
    },
    "name": "TemplateListQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "4bb6f9d73e826b10ea149f3644e08d52";

export default node;
