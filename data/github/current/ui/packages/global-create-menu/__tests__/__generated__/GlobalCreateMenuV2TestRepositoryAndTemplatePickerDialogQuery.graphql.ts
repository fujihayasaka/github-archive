/**
 * @generated SignedSource<<02f2589e080673e8f6f489ff4e42e8c1>>
 * @relayHash 8931741369ada440e9f27a9009812148
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 8931741369ada440e9f27a9009812148

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery$variables = {
  id: string;
};
export type GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"TemplateListPane">;
  } | null | undefined;
};
export type GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery = {
  response: GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery$data;
  variables: GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery$variables;
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
    "name": "GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery",
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
    "name": "GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery",
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
    "id": "8931741369ada440e9f27a9009812148",
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
    "name": "GlobalCreateMenuV2TestRepositoryAndTemplatePickerDialogQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "0969112fd7bdac6449035f58ad0b2e0b";

export default node;
