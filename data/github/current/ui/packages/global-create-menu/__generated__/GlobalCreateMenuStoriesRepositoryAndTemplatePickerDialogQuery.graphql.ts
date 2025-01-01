/**
 * @generated SignedSource<<d5e02f641e6868e87a6fb98ac8666c1e>>
 * @relayHash 22354851953f9afba7cb8d141db1b375
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 22354851953f9afba7cb8d141db1b375

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
  "type": "URI"
},
v8 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v9 = {
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
            "type": "Repository",
            "abstractKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "22354851953f9afba7cb8d141db1b375",
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
        "node.contactLinks.url": (v7/*: any*/),
        "node.hasAnyTemplates": (v8/*: any*/),
        "node.hasIssuesEnabled": (v8/*: any*/),
        "node.id": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ID"
        },
        "node.isBlankIssuesEnabled": (v8/*: any*/),
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
        "node.issueForms.description": (v9/*: any*/),
        "node.issueForms.filename": (v6/*: any*/),
        "node.issueForms.name": (v6/*: any*/),
        "node.issueTemplates": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTemplate"
        },
        "node.issueTemplates.__typename": (v6/*: any*/),
        "node.issueTemplates.about": (v9/*: any*/),
        "node.issueTemplates.filename": (v6/*: any*/),
        "node.issueTemplates.name": (v6/*: any*/),
        "node.nameWithOwner": (v6/*: any*/),
        "node.securityPolicyUrl": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.templateTreeUrl": (v7/*: any*/),
        "node.viewerCanPush": (v8/*: any*/),
        "node.viewerIssueCreationPermissions": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueCreationPermissions"
        },
        "node.viewerIssueCreationPermissions.triageable": (v8/*: any*/),
        "node.viewerIssueCreationPermissions.typeable": (v8/*: any*/)
      }
    },
    "name": "GlobalCreateMenuStoriesRepositoryAndTemplatePickerDialogQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "20042fe53c209d25c3752a87affbb69e";

export default node;
