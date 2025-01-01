/**
 * @generated SignedSource<<cd2694ebb783e950dedae38ba2ce2506>>
 * @relayHash c2beb0c81b293e2cb64c91ac10d5b82c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c2beb0c81b293e2cb64c91ac10d5b82c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type InternalIssueNewPageWithUrlParamsStoryQuery$variables = {
  assigneeLogins?: string | null | undefined;
  discussionNumber?: number | null | undefined;
  includeDiscussion?: boolean | null | undefined;
  labelNames?: string | null | undefined;
  milestoneTitle?: string | null | undefined;
  name: string;
  owner: string;
  projectNumbers?: ReadonlyArray<number> | null | undefined;
  templateFilter?: string | null | undefined;
  type?: string | null | undefined;
  withAssignees?: boolean | null | undefined;
  withLabels?: boolean | null | undefined;
  withMilestone?: boolean | null | undefined;
  withProjects?: boolean | null | undefined;
  withTemplate?: boolean | null | undefined;
  withTriagePermission?: boolean | null | undefined;
  withType?: boolean | null | undefined;
};
export type InternalIssueNewPageWithUrlParamsStoryQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"InternalIssueNewPageUrlArgumentsMetadata">;
  } | null | undefined;
};
export type InternalIssueNewPageWithUrlParamsStoryQuery = {
  response: InternalIssueNewPageWithUrlParamsStoryQuery$data;
  variables: InternalIssueNewPageWithUrlParamsStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": "",
  "kind": "LocalArgument",
  "name": "assigneeLogins"
},
v1 = {
  "defaultValue": 0,
  "kind": "LocalArgument",
  "name": "discussionNumber"
},
v2 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "includeDiscussion"
},
v3 = {
  "defaultValue": "",
  "kind": "LocalArgument",
  "name": "labelNames"
},
v4 = {
  "defaultValue": "",
  "kind": "LocalArgument",
  "name": "milestoneTitle"
},
v5 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "name"
},
v6 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v7 = {
  "defaultValue": ([]/*: any*/),
  "kind": "LocalArgument",
  "name": "projectNumbers"
},
v8 = {
  "defaultValue": "",
  "kind": "LocalArgument",
  "name": "templateFilter"
},
v9 = {
  "defaultValue": "",
  "kind": "LocalArgument",
  "name": "type"
},
v10 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withAssignees"
},
v11 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withLabels"
},
v12 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withMilestone"
},
v13 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withProjects"
},
v14 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withTemplate"
},
v15 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withTriagePermission"
},
v16 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withType"
},
v17 = [
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
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v23 = {
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
v24 = {
  "kind": "Literal",
  "name": "first",
  "value": 20
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v27 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v28 = [
  (v18/*: any*/),
  (v25/*: any*/),
  (v26/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "number",
    "storageKey": null
  },
  (v27/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "viewerCanUpdate",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "hasReachedItemsLimit",
    "storageKey": null
  },
  (v21/*: any*/)
],
v29 = [
  {
    "kind": "Variable",
    "name": "filename",
    "variableName": "templateFilter"
  }
],
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "filename",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v33 = [
  (v18/*: any*/),
  (v31/*: any*/),
  (v20/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameHTML",
    "storageKey": null
  },
  (v32/*: any*/),
  (v27/*: any*/)
],
v34 = {
  "alias": null,
  "args": [
    (v24/*: any*/),
    {
      "kind": "Literal",
      "name": "orderBy",
      "value": {
        "direction": "ASC",
        "field": "NAME"
      }
    }
  ],
  "concreteType": "LabelConnection",
  "kind": "LinkedField",
  "name": "labels",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "LabelEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Label",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": (v33/*: any*/),
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v35 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v36 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v37 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isCopilot",
      "storageKey": null
    }
  ],
  "type": "Bot",
  "abstractKey": null
},
v38 = {
  "alias": null,
  "args": [
    (v35/*: any*/)
  ],
  "concreteType": "UserConnection",
  "kind": "LinkedField",
  "name": "assignees",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "UserEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "User",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": [
            (v18/*: any*/),
            {
              "kind": "InlineFragment",
              "selections": [
                (v21/*: any*/),
                (v22/*: any*/),
                (v20/*: any*/),
                (v36/*: any*/),
                (v23/*: any*/),
                (v37/*: any*/)
              ],
              "type": "Actor",
              "abstractKey": "__isActor"
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "assignees(first:10)"
},
v39 = [
  (v18/*: any*/),
  (v20/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "isEnabled",
    "storageKey": null
  },
  (v32/*: any*/),
  (v31/*: any*/)
],
v40 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "type",
  "plural": false,
  "selections": (v39/*: any*/),
  "storageKey": null
},
v41 = {
  "kind": "ClientExtension",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__id",
      "storageKey": null
    }
  ]
},
v42 = {
  "alias": "itemId",
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "descriptionHTML",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "placeholder",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "value",
  "storageKey": null
},
v47 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "required",
  "storageKey": null
},
v48 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v49 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Int"
},
v50 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v51 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v52 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "LabelConnection"
},
v53 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "LabelEdge"
},
v54 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Label"
},
v55 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v56 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v57 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v58 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "UserConnection"
},
v59 = {
  "enumValues": null,
  "nullable": true,
  "plural": true,
  "type": "UserEdge"
},
v60 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "User"
},
v61 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v62 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "HTML"
},
v63 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ProjectV2Connection"
},
v64 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v65 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v66 = {
  "enumValues": [
    "BLUE",
    "GRAY",
    "GREEN",
    "ORANGE",
    "PINK",
    "PURPLE",
    "RED",
    "YELLOW"
  ],
  "nullable": false,
  "plural": false,
  "type": "IssueTypeColor"
},
v67 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/),
      (v5/*: any*/),
      (v6/*: any*/),
      (v7/*: any*/),
      (v8/*: any*/),
      (v9/*: any*/),
      (v10/*: any*/),
      (v11/*: any*/),
      (v12/*: any*/),
      (v13/*: any*/),
      (v14/*: any*/),
      (v15/*: any*/),
      (v16/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "InternalIssueNewPageWithUrlParamsStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v17/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "args": [
              {
                "kind": "Variable",
                "name": "assigneeLogins",
                "variableName": "assigneeLogins"
              },
              {
                "kind": "Variable",
                "name": "discussionNumber",
                "variableName": "discussionNumber"
              },
              {
                "kind": "Variable",
                "name": "includeDiscussion",
                "variableName": "includeDiscussion"
              },
              {
                "kind": "Variable",
                "name": "labelNames",
                "variableName": "labelNames"
              },
              {
                "kind": "Variable",
                "name": "milestoneTitle",
                "variableName": "milestoneTitle"
              },
              {
                "kind": "Variable",
                "name": "projectNumbers",
                "variableName": "projectNumbers"
              },
              {
                "kind": "Variable",
                "name": "templateFilter",
                "variableName": "templateFilter"
              },
              {
                "kind": "Variable",
                "name": "type",
                "variableName": "type"
              },
              {
                "kind": "Variable",
                "name": "withAssignees",
                "variableName": "withAssignees"
              },
              {
                "kind": "Variable",
                "name": "withLabels",
                "variableName": "withLabels"
              },
              {
                "kind": "Variable",
                "name": "withMilestone",
                "variableName": "withMilestone"
              },
              {
                "kind": "Variable",
                "name": "withProjects",
                "variableName": "withProjects"
              },
              {
                "kind": "Variable",
                "name": "withTemplate",
                "variableName": "withTemplate"
              },
              {
                "kind": "Variable",
                "name": "withTriagePermission",
                "variableName": "withTriagePermission"
              },
              {
                "kind": "Variable",
                "name": "withType",
                "variableName": "withType"
              }
            ],
            "kind": "FragmentSpread",
            "name": "InternalIssueNewPageUrlArgumentsMetadata"
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
      (v6/*: any*/),
      (v5/*: any*/),
      (v10/*: any*/),
      (v0/*: any*/),
      (v11/*: any*/),
      (v3/*: any*/),
      (v12/*: any*/),
      (v4/*: any*/),
      (v9/*: any*/),
      (v16/*: any*/),
      (v13/*: any*/),
      (v7/*: any*/),
      (v15/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v8/*: any*/),
      (v14/*: any*/)
    ],
    "kind": "Operation",
    "name": "InternalIssueNewPageWithUrlParamsStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v17/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v18/*: any*/),
          (v19/*: any*/),
          (v20/*: any*/),
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
              (v21/*: any*/),
              (v19/*: any*/),
              (v22/*: any*/),
              (v23/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "issueTypesEnabled",
                "storageKey": null
              },
              (v18/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "condition": "withProjects",
                    "kind": "Condition",
                    "passingValue": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": [
                          (v24/*: any*/),
                          {
                            "kind": "Variable",
                            "name": "numbers",
                            "variableName": "projectNumbers"
                          }
                        ],
                        "concreteType": "ProjectV2Connection",
                        "kind": "LinkedField",
                        "name": "projectsV2ByNumber",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "ProjectV2",
                            "kind": "LinkedField",
                            "name": "nodes",
                            "plural": true,
                            "selections": (v28/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ]
                  }
                ],
                "type": "ProjectV2Owner",
                "abstractKey": "__isProjectV2Owner"
              }
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
            "kind": "ScalarField",
            "name": "isBlankIssuesEnabled",
            "storageKey": null
          },
          {
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
            "name": "supportFileUrl",
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
          },
          {
            "condition": "withTemplate",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": (v29/*: any*/),
                "concreteType": "IssueTemplate",
                "kind": "LinkedField",
                "name": "issueTemplate",
                "plural": false,
                "selections": [
                  (v21/*: any*/),
                  (v20/*: any*/),
                  (v30/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "body",
                    "storageKey": null
                  },
                  (v25/*: any*/),
                  (v34/*: any*/),
                  (v38/*: any*/),
                  (v40/*: any*/),
                  (v41/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v29/*: any*/),
                "concreteType": "IssueForm",
                "kind": "LinkedField",
                "name": "issueForm",
                "plural": false,
                "selections": [
                  (v21/*: any*/),
                  (v20/*: any*/),
                  (v30/*: any*/),
                  (v25/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "elements",
                    "plural": true,
                    "selections": [
                      (v21/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v42/*: any*/),
                          (v43/*: any*/),
                          (v44/*: any*/),
                          (v45/*: any*/),
                          (v46/*: any*/),
                          (v47/*: any*/),
                          (v41/*: any*/)
                        ],
                        "type": "IssueFormElementInput",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v42/*: any*/),
                          (v43/*: any*/),
                          (v44/*: any*/),
                          (v45/*: any*/),
                          (v46/*: any*/),
                          (v47/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "render",
                            "storageKey": null
                          },
                          (v41/*: any*/)
                        ],
                        "type": "IssueFormElementTextarea",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "contentHTML",
                            "storageKey": null
                          }
                        ],
                        "type": "IssueFormElementMarkdown",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v43/*: any*/),
                          (v44/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "options",
                            "storageKey": null
                          },
                          (v47/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "multiple",
                            "storageKey": null
                          },
                          {
                            "alias": "defaultOptionIndex",
                            "args": null,
                            "kind": "ScalarField",
                            "name": "default",
                            "storageKey": null
                          },
                          (v41/*: any*/)
                        ],
                        "type": "IssueFormElementDropdown",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v43/*: any*/),
                          (v44/*: any*/),
                          {
                            "alias": "checkboxOptions",
                            "args": null,
                            "concreteType": "IssueFormElementCheckboxOption",
                            "kind": "LinkedField",
                            "name": "options",
                            "plural": true,
                            "selections": [
                              (v43/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "labelHTML",
                                "storageKey": null
                              },
                              (v47/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v41/*: any*/)
                        ],
                        "type": "IssueFormElementCheckboxes",
                        "abstractKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v34/*: any*/),
                  (v38/*: any*/),
                  {
                    "alias": null,
                    "args": [
                      (v24/*: any*/)
                    ],
                    "concreteType": "ProjectV2Connection",
                    "kind": "LinkedField",
                    "name": "projects",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "ProjectV2Edge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "ProjectV2",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": (v28/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "projects(first:20)"
                  },
                  (v40/*: any*/),
                  (v41/*: any*/)
                ],
                "storageKey": null
              }
            ]
          },
          {
            "condition": "withAssignees",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "capabilities",
                    "value": [
                      "CAN_BE_ASSIGNED"
                    ]
                  },
                  (v35/*: any*/),
                  {
                    "kind": "Variable",
                    "name": "loginNames",
                    "variableName": "assigneeLogins"
                  }
                ],
                "concreteType": "ActorConnection",
                "kind": "LinkedField",
                "name": "suggestedActors",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v21/*: any*/),
                      {
                        "kind": "TypeDiscriminator",
                        "abstractKey": "__isActor"
                      },
                      (v18/*: any*/),
                      (v22/*: any*/),
                      (v20/*: any*/),
                      (v36/*: any*/),
                      (v23/*: any*/),
                      (v37/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ]
          },
          {
            "condition": "withLabels",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": [
                  (v24/*: any*/),
                  {
                    "kind": "Variable",
                    "name": "names",
                    "variableName": "labelNames"
                  }
                ],
                "concreteType": "LabelConnection",
                "kind": "LinkedField",
                "name": "labels",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "Label",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": (v33/*: any*/),
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ]
          },
          {
            "condition": "includeDiscussion",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Variable",
                    "name": "number",
                    "variableName": "discussionNumber"
                  }
                ],
                "concreteType": "Discussion",
                "kind": "LinkedField",
                "name": "discussion",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "formattedBody",
                    "storageKey": null
                  },
                  (v25/*: any*/),
                  (v34/*: any*/),
                  (v18/*: any*/)
                ],
                "storageKey": null
              }
            ]
          },
          {
            "condition": "withMilestone",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Variable",
                    "name": "title",
                    "variableName": "milestoneTitle"
                  }
                ],
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestoneByTitle",
                "plural": false,
                "selections": [
                  (v18/*: any*/),
                  (v25/*: any*/),
                  (v26/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "dueOn",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "progressPercentage",
                    "storageKey": null
                  },
                  (v27/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "closedAt",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ]
          },
          {
            "condition": "withType",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Variable",
                    "name": "name",
                    "variableName": "type"
                  }
                ],
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "issueType",
                "plural": false,
                "selections": (v39/*: any*/),
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
    "id": "c2beb0c81b293e2cb64c91ac10d5b82c",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.codeOfConductFileUrl": (v48/*: any*/),
        "repository.contributingFileUrl": (v48/*: any*/),
        "repository.databaseId": (v49/*: any*/),
        "repository.discussion": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Discussion"
        },
        "repository.discussion.formattedBody": (v50/*: any*/),
        "repository.discussion.id": (v51/*: any*/),
        "repository.discussion.labels": (v52/*: any*/),
        "repository.discussion.labels.edges": (v53/*: any*/),
        "repository.discussion.labels.edges.node": (v54/*: any*/),
        "repository.discussion.labels.edges.node.color": (v55/*: any*/),
        "repository.discussion.labels.edges.node.description": (v50/*: any*/),
        "repository.discussion.labels.edges.node.id": (v51/*: any*/),
        "repository.discussion.labels.edges.node.name": (v55/*: any*/),
        "repository.discussion.labels.edges.node.nameHTML": (v55/*: any*/),
        "repository.discussion.labels.edges.node.url": (v56/*: any*/),
        "repository.discussion.title": (v55/*: any*/),
        "repository.hasAnyTemplates": (v57/*: any*/),
        "repository.hasIssuesEnabled": (v57/*: any*/),
        "repository.id": (v51/*: any*/),
        "repository.isArchived": (v57/*: any*/),
        "repository.isBlankIssuesEnabled": (v57/*: any*/),
        "repository.isInOrganization": (v57/*: any*/),
        "repository.isPrivate": (v57/*: any*/),
        "repository.issueForm": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueForm"
        },
        "repository.issueForm.__id": (v51/*: any*/),
        "repository.issueForm.__typename": (v55/*: any*/),
        "repository.issueForm.assignees": (v58/*: any*/),
        "repository.issueForm.assignees.edges": (v59/*: any*/),
        "repository.issueForm.assignees.edges.node": (v60/*: any*/),
        "repository.issueForm.assignees.edges.node.__isActor": (v55/*: any*/),
        "repository.issueForm.assignees.edges.node.__typename": (v55/*: any*/),
        "repository.issueForm.assignees.edges.node.avatarUrl": (v56/*: any*/),
        "repository.issueForm.assignees.edges.node.id": (v51/*: any*/),
        "repository.issueForm.assignees.edges.node.isCopilot": (v57/*: any*/),
        "repository.issueForm.assignees.edges.node.login": (v55/*: any*/),
        "repository.issueForm.assignees.edges.node.name": (v50/*: any*/),
        "repository.issueForm.assignees.edges.node.profileResourcePath": (v48/*: any*/),
        "repository.issueForm.elements": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "IssueFormElements"
        },
        "repository.issueForm.elements.__id": (v51/*: any*/),
        "repository.issueForm.elements.__typename": (v55/*: any*/),
        "repository.issueForm.elements.checkboxOptions": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "IssueFormElementCheckboxOption"
        },
        "repository.issueForm.elements.checkboxOptions.label": (v55/*: any*/),
        "repository.issueForm.elements.checkboxOptions.labelHTML": (v55/*: any*/),
        "repository.issueForm.elements.checkboxOptions.required": (v61/*: any*/),
        "repository.issueForm.elements.contentHTML": (v55/*: any*/),
        "repository.issueForm.elements.defaultOptionIndex": (v49/*: any*/),
        "repository.issueForm.elements.descriptionHTML": (v62/*: any*/),
        "repository.issueForm.elements.itemId": (v50/*: any*/),
        "repository.issueForm.elements.label": (v55/*: any*/),
        "repository.issueForm.elements.multiple": (v61/*: any*/),
        "repository.issueForm.elements.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "String"
        },
        "repository.issueForm.elements.placeholder": (v50/*: any*/),
        "repository.issueForm.elements.render": (v50/*: any*/),
        "repository.issueForm.elements.required": (v61/*: any*/),
        "repository.issueForm.elements.value": (v50/*: any*/),
        "repository.issueForm.filename": (v55/*: any*/),
        "repository.issueForm.labels": (v52/*: any*/),
        "repository.issueForm.labels.edges": (v53/*: any*/),
        "repository.issueForm.labels.edges.node": (v54/*: any*/),
        "repository.issueForm.labels.edges.node.color": (v55/*: any*/),
        "repository.issueForm.labels.edges.node.description": (v50/*: any*/),
        "repository.issueForm.labels.edges.node.id": (v51/*: any*/),
        "repository.issueForm.labels.edges.node.name": (v55/*: any*/),
        "repository.issueForm.labels.edges.node.nameHTML": (v55/*: any*/),
        "repository.issueForm.labels.edges.node.url": (v56/*: any*/),
        "repository.issueForm.name": (v55/*: any*/),
        "repository.issueForm.projects": (v63/*: any*/),
        "repository.issueForm.projects.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2Edge"
        },
        "repository.issueForm.projects.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2"
        },
        "repository.issueForm.projects.edges.node.__typename": (v55/*: any*/),
        "repository.issueForm.projects.edges.node.closed": (v57/*: any*/),
        "repository.issueForm.projects.edges.node.hasReachedItemsLimit": (v57/*: any*/),
        "repository.issueForm.projects.edges.node.id": (v51/*: any*/),
        "repository.issueForm.projects.edges.node.number": (v64/*: any*/),
        "repository.issueForm.projects.edges.node.title": (v55/*: any*/),
        "repository.issueForm.projects.edges.node.url": (v56/*: any*/),
        "repository.issueForm.projects.edges.node.viewerCanUpdate": (v57/*: any*/),
        "repository.issueForm.title": (v50/*: any*/),
        "repository.issueForm.type": (v65/*: any*/),
        "repository.issueForm.type.color": (v66/*: any*/),
        "repository.issueForm.type.description": (v50/*: any*/),
        "repository.issueForm.type.id": (v51/*: any*/),
        "repository.issueForm.type.isEnabled": (v57/*: any*/),
        "repository.issueForm.type.name": (v55/*: any*/),
        "repository.issueTemplate": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueTemplate"
        },
        "repository.issueTemplate.__id": (v51/*: any*/),
        "repository.issueTemplate.__typename": (v55/*: any*/),
        "repository.issueTemplate.assignees": (v58/*: any*/),
        "repository.issueTemplate.assignees.edges": (v59/*: any*/),
        "repository.issueTemplate.assignees.edges.node": (v60/*: any*/),
        "repository.issueTemplate.assignees.edges.node.__isActor": (v55/*: any*/),
        "repository.issueTemplate.assignees.edges.node.__typename": (v55/*: any*/),
        "repository.issueTemplate.assignees.edges.node.avatarUrl": (v56/*: any*/),
        "repository.issueTemplate.assignees.edges.node.id": (v51/*: any*/),
        "repository.issueTemplate.assignees.edges.node.isCopilot": (v57/*: any*/),
        "repository.issueTemplate.assignees.edges.node.login": (v55/*: any*/),
        "repository.issueTemplate.assignees.edges.node.name": (v50/*: any*/),
        "repository.issueTemplate.assignees.edges.node.profileResourcePath": (v48/*: any*/),
        "repository.issueTemplate.body": (v50/*: any*/),
        "repository.issueTemplate.filename": (v55/*: any*/),
        "repository.issueTemplate.labels": (v52/*: any*/),
        "repository.issueTemplate.labels.edges": (v53/*: any*/),
        "repository.issueTemplate.labels.edges.node": (v54/*: any*/),
        "repository.issueTemplate.labels.edges.node.color": (v55/*: any*/),
        "repository.issueTemplate.labels.edges.node.description": (v50/*: any*/),
        "repository.issueTemplate.labels.edges.node.id": (v51/*: any*/),
        "repository.issueTemplate.labels.edges.node.name": (v55/*: any*/),
        "repository.issueTemplate.labels.edges.node.nameHTML": (v55/*: any*/),
        "repository.issueTemplate.labels.edges.node.url": (v56/*: any*/),
        "repository.issueTemplate.name": (v55/*: any*/),
        "repository.issueTemplate.title": (v50/*: any*/),
        "repository.issueTemplate.type": (v65/*: any*/),
        "repository.issueTemplate.type.color": (v66/*: any*/),
        "repository.issueTemplate.type.description": (v50/*: any*/),
        "repository.issueTemplate.type.id": (v51/*: any*/),
        "repository.issueTemplate.type.isEnabled": (v57/*: any*/),
        "repository.issueTemplate.type.name": (v55/*: any*/),
        "repository.issueType": (v65/*: any*/),
        "repository.issueType.color": (v66/*: any*/),
        "repository.issueType.description": (v50/*: any*/),
        "repository.issueType.id": (v51/*: any*/),
        "repository.issueType.isEnabled": (v57/*: any*/),
        "repository.issueType.name": (v55/*: any*/),
        "repository.labels": (v52/*: any*/),
        "repository.labels.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Label"
        },
        "repository.labels.nodes.color": (v55/*: any*/),
        "repository.labels.nodes.description": (v50/*: any*/),
        "repository.labels.nodes.id": (v51/*: any*/),
        "repository.labels.nodes.name": (v55/*: any*/),
        "repository.labels.nodes.nameHTML": (v55/*: any*/),
        "repository.labels.nodes.url": (v56/*: any*/),
        "repository.milestoneByTitle": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "repository.milestoneByTitle.closed": (v57/*: any*/),
        "repository.milestoneByTitle.closedAt": (v67/*: any*/),
        "repository.milestoneByTitle.dueOn": (v67/*: any*/),
        "repository.milestoneByTitle.id": (v51/*: any*/),
        "repository.milestoneByTitle.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "repository.milestoneByTitle.title": (v55/*: any*/),
        "repository.milestoneByTitle.url": (v56/*: any*/),
        "repository.name": (v55/*: any*/),
        "repository.nameWithOwner": (v55/*: any*/),
        "repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.owner.__isProjectV2Owner": (v55/*: any*/),
        "repository.owner.__typename": (v55/*: any*/),
        "repository.owner.avatarUrl": (v56/*: any*/),
        "repository.owner.databaseId": (v49/*: any*/),
        "repository.owner.id": (v51/*: any*/),
        "repository.owner.issueTypesEnabled": (v57/*: any*/),
        "repository.owner.login": (v55/*: any*/),
        "repository.owner.projectsV2ByNumber": (v63/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2"
        },
        "repository.owner.projectsV2ByNumber.nodes.__typename": (v55/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.closed": (v57/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.hasReachedItemsLimit": (v57/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.id": (v51/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.number": (v64/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.title": (v55/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.url": (v56/*: any*/),
        "repository.owner.projectsV2ByNumber.nodes.viewerCanUpdate": (v57/*: any*/),
        "repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "repository.planFeatures.maximumAssignees": (v64/*: any*/),
        "repository.securityPolicyUrl": (v48/*: any*/),
        "repository.shortDescriptionHTML": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "HTML"
        },
        "repository.slashCommandsEnabled": (v57/*: any*/),
        "repository.suggestedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ActorConnection"
        },
        "repository.suggestedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Actor"
        },
        "repository.suggestedActors.nodes.__isActor": (v55/*: any*/),
        "repository.suggestedActors.nodes.__typename": (v55/*: any*/),
        "repository.suggestedActors.nodes.avatarUrl": (v56/*: any*/),
        "repository.suggestedActors.nodes.id": (v51/*: any*/),
        "repository.suggestedActors.nodes.isCopilot": (v57/*: any*/),
        "repository.suggestedActors.nodes.login": (v55/*: any*/),
        "repository.suggestedActors.nodes.name": (v50/*: any*/),
        "repository.suggestedActors.nodes.profileResourcePath": (v48/*: any*/),
        "repository.supportFileUrl": (v48/*: any*/),
        "repository.viewerCanPush": (v57/*: any*/),
        "repository.viewerInteractionLimitReasonHTML": (v62/*: any*/),
        "repository.viewerIssueCreationPermissions": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueCreationPermissions"
        },
        "repository.viewerIssueCreationPermissions.assignable": (v57/*: any*/),
        "repository.viewerIssueCreationPermissions.labelable": (v57/*: any*/),
        "repository.viewerIssueCreationPermissions.milestoneable": (v57/*: any*/),
        "repository.viewerIssueCreationPermissions.triageable": (v57/*: any*/),
        "repository.viewerIssueCreationPermissions.typeable": (v57/*: any*/),
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
    "name": "InternalIssueNewPageWithUrlParamsStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "bc23bd646808599b233d477e0805e1c8";

export default node;
