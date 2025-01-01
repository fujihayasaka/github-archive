/**
 * @generated SignedSource<<d78a6b9b7cbb1bbd943148675fd4664f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type InternalIssueNewPageUrlArgumentsMetadata$data = {
  readonly discussion?: {
    readonly formattedBody: string | null | undefined;
    readonly labels: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
        } | null | undefined;
      } | null | undefined> | null | undefined;
    } | null | undefined;
    readonly title: string;
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
  readonly suggestedActors?: {
    readonly nodes: ReadonlyArray<{
      readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
    } | null | undefined> | null | undefined;
  };
  readonly viewerIssueCreationPermissions: {
    readonly assignable?: boolean;
    readonly labelable?: boolean;
    readonly milestoneable?: boolean;
    readonly triageable?: boolean;
    readonly typeable?: boolean;
  };
  readonly " $fragmentSpreads": FragmentRefs<"IssueCreatePage">;
  readonly " $fragmentType": "InternalIssueNewPageUrlArgumentsMetadata";
};
export type InternalIssueNewPageUrlArgumentsMetadata$key = {
  readonly " $data"?: InternalIssueNewPageUrlArgumentsMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"InternalIssueNewPageUrlArgumentsMetadata">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
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
  "name": "name",
  "storageKey": null
},
v3 = {
  "kind": "Literal",
  "name": "first",
  "value": 20
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v7 = [
  {
    "kind": "InlineDataFragmentSpread",
    "name": "LabelPickerLabel",
    "selections": [
      (v1/*: any*/),
      (v4/*: any*/),
      (v2/*: any*/),
      {
        "alias": null,
        "args": null,
        "kind": "ScalarField",
        "name": "nameHTML",
        "storageKey": null
      },
      (v5/*: any*/),
      (v6/*: any*/)
    ],
    "args": null,
    "argumentDefinitions": ([]/*: any*/)
  }
],
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": "",
      "kind": "LocalArgument",
      "name": "assigneeLogins"
    },
    {
      "defaultValue": 0,
      "kind": "LocalArgument",
      "name": "discussionNumber"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "includeDiscussion"
    },
    {
      "defaultValue": "",
      "kind": "LocalArgument",
      "name": "labelNames"
    },
    {
      "defaultValue": "",
      "kind": "LocalArgument",
      "name": "milestoneTitle"
    },
    {
      "defaultValue": [],
      "kind": "LocalArgument",
      "name": "projectNumbers"
    },
    {
      "defaultValue": "",
      "kind": "LocalArgument",
      "name": "templateFilter"
    },
    {
      "defaultValue": "",
      "kind": "LocalArgument",
      "name": "type"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withAssignees"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withLabels"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withMilestone"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withProjects"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withTemplate"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withTriagePermission"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withType"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "InternalIssueNewPageUrlArgumentsMetadata",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "templateFilter",
          "variableName": "templateFilter"
        },
        {
          "kind": "Variable",
          "name": "withTemplate",
          "variableName": "withTemplate"
        }
      ],
      "kind": "FragmentSpread",
      "name": "IssueCreatePage"
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
                {
                  "kind": "InlineDataFragmentSpread",
                  "name": "AssigneePickerAssignee",
                  "selections": [
                    (v0/*: any*/),
                    (v1/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "login",
                      "storageKey": null
                    },
                    (v2/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "profileResourcePath",
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
                    {
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
                    }
                  ],
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
          "args": [
            (v3/*: any*/),
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
              "selections": (v7/*: any*/),
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
            (v8/*: any*/),
            {
              "alias": null,
              "args": [
                (v3/*: any*/),
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
                      "selections": (v7/*: any*/),
                      "storageKey": null
                    }
                  ],
                  "storageKey": null
                }
              ],
              "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
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
            {
              "kind": "InlineDataFragmentSpread",
              "name": "MilestonePickerMilestone",
              "selections": [
                (v1/*: any*/),
                (v8/*: any*/),
                (v9/*: any*/),
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
                (v6/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "closedAt",
                  "storageKey": null
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
          "selections": [
            {
              "kind": "InlineDataFragmentSpread",
              "name": "IssueTypePickerIssueType",
              "selections": [
                (v1/*: any*/),
                (v2/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "isEnabled",
                  "storageKey": null
                },
                (v5/*: any*/),
                (v4/*: any*/)
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
                  "args": [
                    (v3/*: any*/),
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
                      "selections": [
                        {
                          "kind": "InlineDataFragmentSpread",
                          "name": "ProjectPickerProject",
                          "selections": [
                            (v1/*: any*/),
                            (v8/*: any*/),
                            (v9/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "number",
                              "storageKey": null
                            },
                            (v6/*: any*/),
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
                            (v0/*: any*/)
                          ],
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
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "dac38b907bfbe6c2a2a8f9965ee260a2";

export default node;
