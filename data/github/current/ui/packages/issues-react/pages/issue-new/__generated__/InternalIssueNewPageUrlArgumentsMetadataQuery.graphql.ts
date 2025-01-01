/**
 * @generated SignedSource<<a415ee10781edc451e9a5106a1bc18aa>>
 * @relayHash 3076cc2bc7b0de0a6f4241fa67065444
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3076cc2bc7b0de0a6f4241fa67065444

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type InternalIssueNewPageUrlArgumentsMetadataQuery$variables = {
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
export type InternalIssueNewPageUrlArgumentsMetadataQuery$data = {
  readonly repository: {
    readonly " $fragmentSpreads": FragmentRefs<"InternalIssueNewPageUrlArgumentsMetadata">;
  } | null | undefined;
};
export type InternalIssueNewPageUrlArgumentsMetadataQuery = {
  response: InternalIssueNewPageUrlArgumentsMetadataQuery$data;
  variables: InternalIssueNewPageUrlArgumentsMetadataQuery$variables;
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
v36 = [
  (v18/*: any*/),
  (v22/*: any*/),
  (v20/*: any*/),
  (v23/*: any*/)
],
v37 = {
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
          "selections": (v36/*: any*/),
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "assignees(first:10)"
},
v38 = [
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
v39 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "type",
  "plural": false,
  "selections": (v38/*: any*/),
  "storageKey": null
},
v40 = {
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
v41 = {
  "alias": "itemId",
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v42 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v43 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "descriptionHTML",
  "storageKey": null
},
v44 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "placeholder",
  "storageKey": null
},
v45 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "value",
  "storageKey": null
},
v46 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "required",
  "storageKey": null
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
    "name": "InternalIssueNewPageUrlArgumentsMetadataQuery",
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
    "name": "InternalIssueNewPageUrlArgumentsMetadataQuery",
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
                  (v37/*: any*/),
                  (v39/*: any*/),
                  (v40/*: any*/)
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
                          (v41/*: any*/),
                          (v42/*: any*/),
                          (v43/*: any*/),
                          (v44/*: any*/),
                          (v45/*: any*/),
                          (v46/*: any*/),
                          (v40/*: any*/)
                        ],
                        "type": "IssueFormElementInput",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v41/*: any*/),
                          (v42/*: any*/),
                          (v43/*: any*/),
                          (v44/*: any*/),
                          (v45/*: any*/),
                          (v46/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "render",
                            "storageKey": null
                          },
                          (v40/*: any*/)
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
                          (v42/*: any*/),
                          (v43/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "options",
                            "storageKey": null
                          },
                          (v46/*: any*/),
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
                          (v40/*: any*/)
                        ],
                        "type": "IssueFormElementDropdown",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v42/*: any*/),
                          (v43/*: any*/),
                          {
                            "alias": "checkboxOptions",
                            "args": null,
                            "concreteType": "IssueFormElementCheckboxOption",
                            "kind": "LinkedField",
                            "name": "options",
                            "plural": true,
                            "selections": [
                              (v42/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "labelHTML",
                                "storageKey": null
                              },
                              (v46/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v40/*: any*/)
                        ],
                        "type": "IssueFormElementCheckboxes",
                        "abstractKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v34/*: any*/),
                  (v37/*: any*/),
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
                  (v39/*: any*/),
                  (v40/*: any*/)
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
                  (v35/*: any*/),
                  {
                    "kind": "Variable",
                    "name": "loginNames",
                    "variableName": "assigneeLogins"
                  }
                ],
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignableUsers",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "User",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": (v36/*: any*/),
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
                "selections": (v38/*: any*/),
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
    "id": "3076cc2bc7b0de0a6f4241fa67065444",
    "metadata": {},
    "name": "InternalIssueNewPageUrlArgumentsMetadataQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "0e2b0b1f573d6b277c23946014ca42d6";

export default node;
