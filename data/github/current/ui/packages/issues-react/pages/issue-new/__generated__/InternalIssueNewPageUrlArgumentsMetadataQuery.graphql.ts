/**
 * @generated SignedSource<<48f478ac67ea00ba53effdf46e029cac>>
 * @relayHash 3e6a6129ce6d5d523026bc51d72a04ae
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3e6a6129ce6d5d523026bc51d72a04ae

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type InternalIssueNewPageUrlArgumentsMetadataQuery$variables = {
  assigneeLogins?: string | null | undefined;
  discussionNumber?: number | null | undefined;
  includeDiscussion?: boolean | null | undefined;
  labelNames?: string | null | undefined;
  milestoneTitle?: string | null | undefined;
  name: string;
  owner: string;
  projectNumbers?: ReadonlyArray<number> | null | undefined;
  type?: string | null | undefined;
  withAnyMetadata?: boolean | null | undefined;
  withAssignees?: boolean | null | undefined;
  withLabels?: boolean | null | undefined;
  withMilestone?: boolean | null | undefined;
  withProjects?: boolean | null | undefined;
  withTriagePermission?: boolean | null | undefined;
  withType?: boolean | null | undefined;
};
export type InternalIssueNewPageUrlArgumentsMetadataQuery$data = {
  readonly repository?: {
    readonly assignableUsers?: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
      } | null | undefined> | null | undefined;
    };
    readonly discussion?: {
      readonly " $fragmentSpreads": FragmentRefs<"CreateIssueDiscussion">;
    } | null | undefined;
    readonly issueType?: {
      readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerIssueType">;
    } | null | undefined;
    readonly labels?: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
      } | null | undefined> | null | undefined;
    } | null | undefined;
    readonly milestoneByTitle?: {
      readonly " $fragmentSpreads": FragmentRefs<"MilestonePickerMilestone">;
    } | null | undefined;
    readonly owner: {
      readonly projectsV2ByNumber?: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
        } | null | undefined> | null | undefined;
      };
    };
    readonly viewerIssueCreationPermissions: {
      readonly assignable?: boolean;
      readonly labelable?: boolean;
      readonly milestoneable?: boolean;
      readonly triageable?: boolean;
      readonly typeable?: boolean;
    };
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
  "name": "type"
},
v9 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withAnyMetadata"
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
  "name": "withTriagePermission"
},
v15 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "withType"
},
v16 = [
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
v17 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueCreationPermissions",
  "kind": "LinkedField",
  "name": "viewerIssueCreationPermissions",
  "plural": false,
  "selections": [
    {
      "condition": "withAssignees",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "assignable",
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
          "args": null,
          "kind": "ScalarField",
          "name": "labelable",
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
          "args": null,
          "kind": "ScalarField",
          "name": "milestoneable",
          "storageKey": null
        }
      ]
    },
    {
      "condition": "withTriagePermission",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "triageable",
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
          "args": null,
          "kind": "ScalarField",
          "name": "typeable",
          "storageKey": null
        }
      ]
    }
  ],
  "storageKey": null
},
v18 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  },
  {
    "kind": "Variable",
    "name": "loginNames",
    "variableName": "assigneeLogins"
  }
],
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v21 = [
  (v19/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
    "storageKey": null
  },
  (v20/*: any*/),
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
  }
],
v22 = {
  "kind": "Literal",
  "name": "first",
  "value": 20
},
v23 = [
  (v22/*: any*/),
  {
    "kind": "Variable",
    "name": "names",
    "variableName": "labelNames"
  }
],
v24 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v26 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v27 = [
  (v19/*: any*/),
  (v24/*: any*/),
  (v20/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameHTML",
    "storageKey": null
  },
  (v25/*: any*/),
  (v26/*: any*/)
],
v28 = [
  {
    "kind": "InlineDataFragmentSpread",
    "name": "LabelPickerLabel",
    "selections": (v27/*: any*/),
    "args": null,
    "argumentDefinitions": ([]/*: any*/)
  }
],
v29 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "discussionNumber"
  }
],
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "formattedBody",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v32 = [
  (v22/*: any*/),
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
v33 = [
  {
    "kind": "Variable",
    "name": "title",
    "variableName": "milestoneTitle"
  }
],
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v35 = [
  (v19/*: any*/),
  (v31/*: any*/),
  (v34/*: any*/),
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
  (v26/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "closedAt",
    "storageKey": null
  }
],
v36 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "type"
  }
],
v37 = [
  (v19/*: any*/),
  (v20/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "isEnabled",
    "storageKey": null
  },
  (v25/*: any*/),
  (v24/*: any*/)
],
v38 = [
  (v22/*: any*/),
  {
    "kind": "Variable",
    "name": "numbers",
    "variableName": "projectNumbers"
  }
],
v39 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v40 = [
  (v19/*: any*/),
  (v31/*: any*/),
  (v34/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "number",
    "storageKey": null
  },
  (v26/*: any*/),
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
  (v39/*: any*/)
];
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
      (v15/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "InternalIssueNewPageUrlArgumentsMetadataQuery",
    "selections": [
      {
        "condition": "withAnyMetadata",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": null,
            "args": (v16/*: any*/),
            "concreteType": "Repository",
            "kind": "LinkedField",
            "name": "repository",
            "plural": false,
            "selections": [
              (v17/*: any*/),
              {
                "condition": "withAssignees",
                "kind": "Condition",
                "passingValue": true,
                "selections": [
                  {
                    "alias": null,
                    "args": (v18/*: any*/),
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
                        "selections": [
                          {
                            "kind": "InlineDataFragmentSpread",
                            "name": "AssigneePickerAssignee",
                            "selections": (v21/*: any*/),
                            "args": null,
                            "argumentDefinitions": []
                          }
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
                    "args": (v23/*: any*/),
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
                        "selections": (v28/*: any*/),
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
                    "args": (v29/*: any*/),
                    "concreteType": "Discussion",
                    "kind": "LinkedField",
                    "name": "discussion",
                    "plural": false,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "CreateIssueDiscussion",
                        "selections": [
                          (v30/*: any*/),
                          (v31/*: any*/),
                          {
                            "alias": null,
                            "args": (v32/*: any*/),
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
                                    "selections": (v28/*: any*/),
                                    "storageKey": null
                                  }
                                ],
                                "storageKey": null
                              }
                            ],
                            "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                          }
                        ],
                        "args": null,
                        "argumentDefinitions": []
                      }
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
                    "args": (v33/*: any*/),
                    "concreteType": "Milestone",
                    "kind": "LinkedField",
                    "name": "milestoneByTitle",
                    "plural": false,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "MilestonePickerMilestone",
                        "selections": (v35/*: any*/),
                        "args": null,
                        "argumentDefinitions": []
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
                    "args": (v36/*: any*/),
                    "concreteType": "IssueType",
                    "kind": "LinkedField",
                    "name": "issueType",
                    "plural": false,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "IssueTypePickerIssueType",
                        "selections": (v37/*: any*/),
                        "args": null,
                        "argumentDefinitions": []
                      }
                    ],
                    "storageKey": null
                  }
                ]
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
                    "kind": "InlineFragment",
                    "selections": [
                      {
                        "condition": "withProjects",
                        "kind": "Condition",
                        "passingValue": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": (v38/*: any*/),
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
                                "selections": [
                                  {
                                    "kind": "InlineDataFragmentSpread",
                                    "name": "ProjectPickerProject",
                                    "selections": (v40/*: any*/),
                                    "args": null,
                                    "argumentDefinitions": []
                                  }
                                ],
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
              }
            ],
            "storageKey": null
          }
        ]
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
      (v9/*: any*/),
      (v10/*: any*/),
      (v0/*: any*/),
      (v11/*: any*/),
      (v3/*: any*/),
      (v12/*: any*/),
      (v4/*: any*/),
      (v8/*: any*/),
      (v15/*: any*/),
      (v13/*: any*/),
      (v7/*: any*/),
      (v14/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Operation",
    "name": "InternalIssueNewPageUrlArgumentsMetadataQuery",
    "selections": [
      {
        "condition": "withAnyMetadata",
        "kind": "Condition",
        "passingValue": true,
        "selections": [
          {
            "alias": null,
            "args": (v16/*: any*/),
            "concreteType": "Repository",
            "kind": "LinkedField",
            "name": "repository",
            "plural": false,
            "selections": [
              (v17/*: any*/),
              {
                "condition": "withAssignees",
                "kind": "Condition",
                "passingValue": true,
                "selections": [
                  {
                    "alias": null,
                    "args": (v18/*: any*/),
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
                        "selections": (v21/*: any*/),
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
                    "args": (v23/*: any*/),
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
                        "selections": (v27/*: any*/),
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
                    "args": (v29/*: any*/),
                    "concreteType": "Discussion",
                    "kind": "LinkedField",
                    "name": "discussion",
                    "plural": false,
                    "selections": [
                      (v30/*: any*/),
                      (v31/*: any*/),
                      {
                        "alias": null,
                        "args": (v32/*: any*/),
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
                                "selections": (v27/*: any*/),
                                "storageKey": null
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                      },
                      (v19/*: any*/)
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
                    "args": (v33/*: any*/),
                    "concreteType": "Milestone",
                    "kind": "LinkedField",
                    "name": "milestoneByTitle",
                    "plural": false,
                    "selections": (v35/*: any*/),
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
                    "args": (v36/*: any*/),
                    "concreteType": "IssueType",
                    "kind": "LinkedField",
                    "name": "issueType",
                    "plural": false,
                    "selections": (v37/*: any*/),
                    "storageKey": null
                  }
                ]
              },
              {
                "alias": null,
                "args": null,
                "concreteType": null,
                "kind": "LinkedField",
                "name": "owner",
                "plural": false,
                "selections": [
                  (v39/*: any*/),
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
                            "args": (v38/*: any*/),
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
                                "selections": (v40/*: any*/),
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
                  },
                  (v19/*: any*/)
                ],
                "storageKey": null
              },
              (v19/*: any*/)
            ],
            "storageKey": null
          }
        ]
      }
    ]
  },
  "params": {
    "id": "3e6a6129ce6d5d523026bc51d72a04ae",
    "metadata": {},
    "name": "InternalIssueNewPageUrlArgumentsMetadataQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "54a440d915536c0164bf7122b70036ec";

export default node;
