/**
 * @generated SignedSource<<d8829db4f12682f73118e2b75acfe651>>
 * @relayHash 5abd2119328a2855eb370c4824507864
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 5abd2119328a2855eb370c4824507864

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DuplicateIssueDialogEntryTestQuery$variables = {
  includeTemplates?: boolean | null | undefined;
  name: string;
  owner: string;
};
export type DuplicateIssueDialogEntryTestQuery$data = {
  readonly repository: {
    readonly hasAnyTemplates: boolean;
    readonly " $fragmentSpreads": FragmentRefs<"CreateIssueDialog" | "RepositoryPickerRepository">;
  } | null | undefined;
};
export type DuplicateIssueDialogEntryTestQuery = {
  response: DuplicateIssueDialogEntryTestQuery$data;
  variables: DuplicateIssueDialogEntryTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "includeTemplates"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "name"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasAnyTemplates",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameWithOwner",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v10 = {
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
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "issueTypesEnabled",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "visibility",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInOrganization",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasIssuesEnabled",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanPush",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isBlankIssuesEnabled",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "action",
      "value": "create an issue"
    }
  ],
  "kind": "ScalarField",
  "name": "viewerInteractionLimitReasonHTML",
  "storageKey": "viewerInteractionLimitReasonHTML(action:\"create an issue\")"
},
v21 = {
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
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "securityPolicyUrl",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "contributingFileUrl",
  "storageKey": null
},
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "codeOfConductFileUrl",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "supportFileUrl",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "shortDescriptionHTML",
  "storageKey": null
},
v27 = {
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
v28 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "filename",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "about",
  "storageKey": null
},
v31 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v32 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v34 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v36 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v37 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "DuplicateIssueDialogEntryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          {
            "kind": "InlineDataFragmentSpread",
            "name": "RepositoryPickerRepository",
            "selections": [
              (v5/*: any*/),
              (v6/*: any*/),
              (v7/*: any*/),
              (v8/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "owner",
                "plural": false,
                "selections": [
                  (v6/*: any*/),
                  (v9/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/)
                ],
                "storageKey": null
              },
              (v12/*: any*/),
              (v13/*: any*/),
              (v14/*: any*/),
              (v15/*: any*/),
              (v16/*: any*/),
              (v17/*: any*/),
              (v18/*: any*/),
              (v19/*: any*/),
              (v20/*: any*/),
              (v21/*: any*/),
              (v22/*: any*/),
              (v23/*: any*/),
              (v24/*: any*/),
              (v25/*: any*/),
              (v26/*: any*/),
              (v27/*: any*/)
            ],
            "args": null,
            "argumentDefinitions": []
          },
          {
            "args": [
              {
                "kind": "Variable",
                "name": "includeTemplates",
                "variableName": "includeTemplates"
              }
            ],
            "kind": "FragmentSpread",
            "name": "CreateIssueDialog"
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
    "argumentDefinitions": [
      (v2/*: any*/),
      (v1/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "DuplicateIssueDialogEntryTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          (v5/*: any*/),
          (v6/*: any*/),
          (v7/*: any*/),
          (v8/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "owner",
            "plural": false,
            "selections": [
              (v28/*: any*/),
              (v6/*: any*/),
              (v9/*: any*/),
              (v10/*: any*/),
              (v11/*: any*/),
              (v5/*: any*/)
            ],
            "storageKey": null
          },
          (v12/*: any*/),
          (v13/*: any*/),
          (v14/*: any*/),
          (v15/*: any*/),
          (v16/*: any*/),
          (v17/*: any*/),
          (v18/*: any*/),
          (v19/*: any*/),
          (v20/*: any*/),
          (v21/*: any*/),
          (v22/*: any*/),
          (v23/*: any*/),
          (v24/*: any*/),
          (v25/*: any*/),
          (v26/*: any*/),
          (v27/*: any*/),
          {
            "condition": "includeTemplates",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueForm",
                "kind": "LinkedField",
                "name": "issueForms",
                "plural": true,
                "selections": [
                  (v28/*: any*/),
                  (v29/*: any*/),
                  (v7/*: any*/),
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
                  (v28/*: any*/),
                  (v29/*: any*/),
                  (v7/*: any*/),
                  (v30/*: any*/)
                ],
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
                "concreteType": "RepositoryContactLink",
                "kind": "LinkedField",
                "name": "contactLinks",
                "plural": true,
                "selections": [
                  (v7/*: any*/),
                  (v30/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "url",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ]
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "5abd2119328a2855eb370c4824507864",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.codeOfConductFileUrl": (v31/*: any*/),
        "repository.contactLinks": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "RepositoryContactLink"
        },
        "repository.contactLinks.about": (v32/*: any*/),
        "repository.contactLinks.name": (v32/*: any*/),
        "repository.contactLinks.url": (v33/*: any*/),
        "repository.contributingFileUrl": (v31/*: any*/),
        "repository.databaseId": (v34/*: any*/),
        "repository.hasAnyTemplates": (v35/*: any*/),
        "repository.hasIssuesEnabled": (v35/*: any*/),
        "repository.id": (v36/*: any*/),
        "repository.isArchived": (v35/*: any*/),
        "repository.isBlankIssuesEnabled": (v35/*: any*/),
        "repository.isInOrganization": (v35/*: any*/),
        "repository.isPrivate": (v35/*: any*/),
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
        "repository.issueForms.__typename": (v32/*: any*/),
        "repository.issueForms.description": (v37/*: any*/),
        "repository.issueForms.filename": (v32/*: any*/),
        "repository.issueForms.name": (v32/*: any*/),
        "repository.issueTemplates": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTemplate"
        },
        "repository.issueTemplates.__typename": (v32/*: any*/),
        "repository.issueTemplates.about": (v37/*: any*/),
        "repository.issueTemplates.filename": (v32/*: any*/),
        "repository.issueTemplates.name": (v32/*: any*/),
        "repository.name": (v32/*: any*/),
        "repository.nameWithOwner": (v32/*: any*/),
        "repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.owner.__typename": (v32/*: any*/),
        "repository.owner.avatarUrl": (v33/*: any*/),
        "repository.owner.databaseId": (v34/*: any*/),
        "repository.owner.id": (v36/*: any*/),
        "repository.owner.issueTypesEnabled": (v35/*: any*/),
        "repository.owner.login": (v32/*: any*/),
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
        "repository.securityPolicyUrl": (v31/*: any*/),
        "repository.shortDescriptionHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "repository.slashCommandsEnabled": (v35/*: any*/),
        "repository.supportFileUrl": (v31/*: any*/),
        "repository.viewerCanPush": (v35/*: any*/),
        "repository.viewerInteractionLimitReasonHTML": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "HTML"
        },
        "repository.viewerIssueCreationPermissions": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueCreationPermissions"
        },
        "repository.viewerIssueCreationPermissions.assignable": (v35/*: any*/),
        "repository.viewerIssueCreationPermissions.labelable": (v35/*: any*/),
        "repository.viewerIssueCreationPermissions.milestoneable": (v35/*: any*/),
        "repository.viewerIssueCreationPermissions.triageable": (v35/*: any*/),
        "repository.viewerIssueCreationPermissions.typeable": (v35/*: any*/),
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
    "name": "DuplicateIssueDialogEntryTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "6b86261b9987b51775d6aaf406c28861";

export default node;
