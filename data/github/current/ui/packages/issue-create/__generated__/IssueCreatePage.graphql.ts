/**
 * @generated SignedSource<<00fe13bd5015d50bd251cf95e40ad36b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueCreatePage$data = {
  readonly hasAnyTemplates: boolean;
  readonly name: string;
  readonly owner: {
    readonly login: string;
  };
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryPickerRepository" | "useHandleTemplateChange">;
  readonly " $fragmentType": "IssueCreatePage";
};
export type IssueCreatePage$key = {
  readonly " $data"?: IssueCreatePage$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCreatePage">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v4 = {
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
v5 = [
  {
    "kind": "Variable",
    "name": "filename",
    "variableName": "filename"
  }
],
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "filename",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v9 = {
  "kind": "Literal",
  "name": "first",
  "value": 20
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": [
    (v9/*: any*/),
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
          "selections": [
            {
              "kind": "InlineDataFragmentSpread",
              "name": "LabelPickerLabel",
              "selections": [
                (v0/*: any*/),
                (v10/*: any*/),
                (v2/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "nameHTML",
                  "storageKey": null
                },
                (v11/*: any*/),
                (v12/*: any*/)
              ],
              "args": null,
              "argumentDefinitions": ([]/*: any*/)
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v14 = {
  "alias": null,
  "args": [
    {
      "kind": "Literal",
      "name": "first",
      "value": 10
    }
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
            {
              "kind": "InlineDataFragmentSpread",
              "name": "AssigneePickerAssignee",
              "selections": [
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v6/*: any*/),
                    (v0/*: any*/),
                    (v3/*: any*/),
                    (v2/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "profileResourcePath",
                      "storageKey": null
                    },
                    (v4/*: any*/),
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
                  "type": "Actor",
                  "abstractKey": "__isActor"
                }
              ],
              "args": null,
              "argumentDefinitions": ([]/*: any*/)
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
v15 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "type",
  "plural": false,
  "selections": [
    {
      "kind": "InlineDataFragmentSpread",
      "name": "IssueTypePickerIssueType",
      "selections": [
        (v0/*: any*/),
        (v2/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isEnabled",
          "storageKey": null
        },
        (v11/*: any*/),
        (v10/*: any*/)
      ],
      "args": null,
      "argumentDefinitions": ([]/*: any*/)
    }
  ],
  "storageKey": null
},
v16 = {
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
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": "",
      "kind": "LocalArgument",
      "name": "templateFilter"
    },
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "withTemplate"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCreatePage",
  "selections": [
    {
      "kind": "InlineDataFragmentSpread",
      "name": "RepositoryPickerRepository",
      "selections": [
        (v0/*: any*/),
        (v1/*: any*/),
        (v2/*: any*/),
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
            (v1/*: any*/),
            (v3/*: any*/),
            (v4/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "issueTypesEnabled",
              "storageKey": null
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
        }
      ],
      "args": null,
      "argumentDefinitions": []
    },
    (v2/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        (v3/*: any*/)
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
          "kind": "InlineDataFragmentSpread",
          "name": "useHandleTemplateChange",
          "selections": [
            {
              "alias": null,
              "args": (v5/*: any*/),
              "concreteType": "IssueTemplate",
              "kind": "LinkedField",
              "name": "issueTemplate",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineDataFragmentSpread",
                  "name": "useHandleTemplateChangeIssueTemplate",
                  "selections": [
                    (v6/*: any*/),
                    (v2/*: any*/),
                    (v7/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "kind": "ScalarField",
                      "name": "body",
                      "storageKey": null
                    },
                    (v8/*: any*/),
                    (v13/*: any*/),
                    (v14/*: any*/),
                    (v15/*: any*/),
                    (v16/*: any*/)
                  ],
                  "args": null,
                  "argumentDefinitions": []
                }
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v5/*: any*/),
              "concreteType": "IssueForm",
              "kind": "LinkedField",
              "name": "issueForm",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineDataFragmentSpread",
                  "name": "useHandleTemplateChangeIssueForm",
                  "selections": [
                    (v6/*: any*/),
                    (v2/*: any*/),
                    (v7/*: any*/),
                    (v8/*: any*/),
                    {
                      "kind": "InlineDataFragmentSpread",
                      "name": "IssueFormElements_templateElements",
                      "selections": [
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": null,
                          "kind": "LinkedField",
                          "name": "elements",
                          "plural": true,
                          "selections": [
                            (v6/*: any*/),
                            {
                              "kind": "InlineFragment",
                              "selections": [
                                {
                                  "args": null,
                                  "kind": "FragmentSpread",
                                  "name": "TextInputElement_input"
                                }
                              ],
                              "type": "IssueFormElementInput",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": [
                                {
                                  "args": null,
                                  "kind": "FragmentSpread",
                                  "name": "TextAreaElement_input"
                                }
                              ],
                              "type": "IssueFormElementTextarea",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": [
                                {
                                  "args": null,
                                  "kind": "FragmentSpread",
                                  "name": "MarkdownElement_input"
                                }
                              ],
                              "type": "IssueFormElementMarkdown",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": [
                                {
                                  "args": null,
                                  "kind": "FragmentSpread",
                                  "name": "DropdownElement_input"
                                }
                              ],
                              "type": "IssueFormElementDropdown",
                              "abstractKey": null
                            },
                            {
                              "kind": "InlineFragment",
                              "selections": [
                                {
                                  "args": null,
                                  "kind": "FragmentSpread",
                                  "name": "CheckboxesElement_input"
                                }
                              ],
                              "type": "IssueFormElementCheckboxes",
                              "abstractKey": null
                            }
                          ],
                          "storageKey": null
                        }
                      ],
                      "args": null,
                      "argumentDefinitions": []
                    },
                    (v13/*: any*/),
                    (v14/*: any*/),
                    {
                      "alias": null,
                      "args": [
                        (v9/*: any*/)
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
                              "selections": [
                                {
                                  "kind": "InlineDataFragmentSpread",
                                  "name": "ProjectPickerProject",
                                  "selections": [
                                    (v0/*: any*/),
                                    (v8/*: any*/),
                                    {
                                      "alias": null,
                                      "args": null,
                                      "kind": "ScalarField",
                                      "name": "closed",
                                      "storageKey": null
                                    },
                                    {
                                      "alias": null,
                                      "args": null,
                                      "kind": "ScalarField",
                                      "name": "number",
                                      "storageKey": null
                                    },
                                    (v12/*: any*/),
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
                                    (v6/*: any*/)
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
                      ],
                      "storageKey": "projects(first:20)"
                    },
                    (v15/*: any*/),
                    (v16/*: any*/)
                  ],
                  "args": null,
                  "argumentDefinitions": []
                }
              ],
              "storageKey": null
            }
          ],
          "args": [
            {
              "kind": "Variable",
              "name": "filename",
              "variableName": "templateFilter"
            }
          ],
          "argumentDefinitions": [
            {
              "defaultValue": "",
              "kind": "LocalArgument",
              "name": "filename"
            }
          ]
        }
      ]
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "22ff6992a96ef2cde9444260d48f9173";

export default node;
