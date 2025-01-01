/**
 * @generated SignedSource<<80d237be7508a28eb8699ca19c948275>>
 * @relayHash f867859d9778adb7bfc9b3cf7e907867
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f867859d9778adb7bfc9b3cf7e907867

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery$variables = {
  id: string;
};
export type GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"TemplateListPane">;
  } | null | undefined;
};
export type GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery = {
  response: GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery$data;
  variables: GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "filename",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "about",
  "storageKey": null
},
v6 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "TemplateListPane"
              }
            ],
            "type": "Repository",
            "abstractKey": null
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
    "name": "GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
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
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
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
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v5/*: any*/)
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
                  (v4/*: any*/),
                  (v5/*: any*/),
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
              }
            ],
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "f867859d9778adb7bfc9b3cf7e907867",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v6/*: any*/),
        "node.contactLinks": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "RepositoryContactLink"
        },
        "node.contactLinks.about": (v6/*: any*/),
        "node.contactLinks.name": (v6/*: any*/),
        "node.contactLinks.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "node.hasAnyTemplates": (v7/*: any*/),
        "node.hasIssuesEnabled": (v7/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.isBlankIssuesEnabled": (v7/*: any*/),
        "node.isSecurityPolicyEnabled": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        },
        "node.issueForms": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueForm"
        },
        "node.issueForms.__typename": (v6/*: any*/),
        "node.issueForms.description": (v8/*: any*/),
        "node.issueForms.filename": (v6/*: any*/),
        "node.issueForms.name": (v6/*: any*/),
        "node.issueTemplates": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTemplate"
        },
        "node.issueTemplates.__typename": (v6/*: any*/),
        "node.issueTemplates.about": (v8/*: any*/),
        "node.issueTemplates.filename": (v6/*: any*/),
        "node.issueTemplates.name": (v6/*: any*/),
        "node.nameWithOwner": (v6/*: any*/),
        "node.securityPolicyUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        }
      }
    },
    "name": "GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e93bf461114d5972ce42e37f60de18ae";

export default node;
