/**
 * @generated SignedSource<<733d1050c363ecd4c5ff3a78c0cd40ef>>
 * @relayHash fcbd0fb15e7d594d13a3d1e37659952b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID fcbd0fb15e7d594d13a3d1e37659952b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueCreateDialogWebComponentQuery$variables = {
  id: string;
};
export type IssueCreateDialogWebComponentQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"CreateIssueDialog" | "RepositoryPickerRepository">;
  } | null | undefined;
};
export type IssueCreateDialogWebComponentQuery = {
  response: IssueCreateDialogWebComponentQuery$data;
  variables: IssueCreateDialogWebComponentQuery$variables;
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
  "name": "id",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
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
  "name": "nameWithOwner",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v7 = {
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
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "issueTypesEnabled",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isPrivate",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "visibility",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isInOrganization",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "hasIssuesEnabled",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "slashCommandsEnabled",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanPush",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isBlankIssuesEnabled",
  "storageKey": null
},
v17 = {
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
v18 = {
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
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "securityPolicyUrl",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "contributingFileUrl",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "codeOfConductFileUrl",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "supportFileUrl",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "shortDescriptionHTML",
  "storageKey": null
},
v24 = {
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
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v27 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v28 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueCreateDialogWebComponentQuery",
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
                "kind": "InlineDataFragmentSpread",
                "name": "RepositoryPickerRepository",
                "selections": [
                  (v2/*: any*/),
                  (v3/*: any*/),
                  (v4/*: any*/),
                  (v5/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v3/*: any*/),
                      (v6/*: any*/),
                      (v7/*: any*/),
                      (v8/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v9/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/),
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
                  (v24/*: any*/)
                ],
                "args": null,
                "argumentDefinitions": []
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "CreateIssueDialog"
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
    "name": "IssueCreateDialogWebComponentQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v25/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              (v4/*: any*/),
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "owner",
                "plural": false,
                "selections": [
                  (v25/*: any*/),
                  (v3/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
                  (v2/*: any*/)
                ],
                "storageKey": null
              },
              (v9/*: any*/),
              (v10/*: any*/),
              (v11/*: any*/),
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
              (v24/*: any*/)
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
    "id": "fcbd0fb15e7d594d13a3d1e37659952b",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__typename": (v26/*: any*/),
        "node.codeOfConductFileUrl": (v27/*: any*/),
        "node.contributingFileUrl": (v27/*: any*/),
        "node.databaseId": (v28/*: any*/),
        "node.hasIssuesEnabled": (v29/*: any*/),
        "node.id": (v30/*: any*/),
        "node.isArchived": (v29/*: any*/),
        "node.isBlankIssuesEnabled": (v29/*: any*/),
        "node.isInOrganization": (v29/*: any*/),
        "node.isPrivate": (v29/*: any*/),
        "node.name": (v26/*: any*/),
        "node.nameWithOwner": (v26/*: any*/),
        "node.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "node.owner.__typename": (v26/*: any*/),
        "node.owner.avatarUrl": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "node.owner.databaseId": (v28/*: any*/),
        "node.owner.id": (v30/*: any*/),
        "node.owner.issueTypesEnabled": (v29/*: any*/),
        "node.owner.login": (v26/*: any*/),
        "node.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "node.planFeatures.maximumAssignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Int"
        },
        "node.securityPolicyUrl": (v27/*: any*/),
        "node.shortDescriptionHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "node.slashCommandsEnabled": (v29/*: any*/),
        "node.supportFileUrl": (v27/*: any*/),
        "node.viewerCanPush": (v29/*: any*/),
        "node.viewerInteractionLimitReasonHTML": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "HTML"
        },
        "node.viewerIssueCreationPermissions": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueCreationPermissions"
        },
        "node.viewerIssueCreationPermissions.assignable": (v29/*: any*/),
        "node.viewerIssueCreationPermissions.labelable": (v29/*: any*/),
        "node.viewerIssueCreationPermissions.milestoneable": (v29/*: any*/),
        "node.viewerIssueCreationPermissions.triageable": (v29/*: any*/),
        "node.viewerIssueCreationPermissions.typeable": (v29/*: any*/),
        "node.visibility": {
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
    "name": "IssueCreateDialogWebComponentQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "8f6aed8b00887adb107559c582a70450";

export default node;
