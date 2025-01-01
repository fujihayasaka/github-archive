/**
 * @generated SignedSource<<ec8c9a6cd9f50922e62813413e64ff16>>
 * @relayHash 4ffbcb331b611999ef714eedde0b3d0b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 4ffbcb331b611999ef714eedde0b3d0b

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type CreateIssueQuery$variables = {
  filename: string;
  repoId: string;
};
export type CreateIssueQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"useHandleTemplateChange">;
  } | null | undefined;
};
export type CreateIssueQuery = {
  response: CreateIssueQuery$data;
  variables: CreateIssueQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "filename"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repoId"
},
v2 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "repoId"
  }
],
v3 = [
  {
    "kind": "Variable",
    "name": "filename",
    "variableName": "filename"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "filename",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
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
v10 = [
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
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v15 = [
  (v11/*: any*/),
  (v12/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameHTML",
    "storageKey": null
  },
  (v13/*: any*/),
  (v14/*: any*/)
],
v16 = {
  "alias": null,
  "args": (v10/*: any*/),
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
              "selections": (v15/*: any*/),
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
v17 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
  "storageKey": null
},
v20 = {
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
v21 = {
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
v22 = {
  "alias": null,
  "args": (v17/*: any*/),
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
                    (v4/*: any*/),
                    (v11/*: any*/),
                    (v18/*: any*/),
                    (v5/*: any*/),
                    (v19/*: any*/),
                    (v20/*: any*/),
                    (v21/*: any*/)
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
v23 = [
  (v11/*: any*/),
  (v5/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "isEnabled",
    "storageKey": null
  },
  (v13/*: any*/),
  (v12/*: any*/)
],
v24 = {
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
      "selections": (v23/*: any*/),
      "args": null,
      "argumentDefinitions": ([]/*: any*/)
    }
  ],
  "storageKey": null
},
v25 = {
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
v26 = [
  (v9/*: any*/)
],
v27 = [
  (v11/*: any*/),
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
  (v14/*: any*/),
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
  (v4/*: any*/)
],
v28 = {
  "alias": null,
  "args": (v10/*: any*/),
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
          "selections": (v15/*: any*/),
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "labels(first:20,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
},
v29 = {
  "alias": null,
  "args": (v17/*: any*/),
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
            (v11/*: any*/),
            {
              "kind": "InlineFragment",
              "selections": [
                (v4/*: any*/),
                (v18/*: any*/),
                (v5/*: any*/),
                (v19/*: any*/),
                (v20/*: any*/),
                (v21/*: any*/)
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
v30 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "type",
  "plural": false,
  "selections": (v23/*: any*/),
  "storageKey": null
},
v31 = {
  "alias": "itemId",
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v33 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "descriptionHTML",
  "storageKey": null
},
v34 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "placeholder",
  "storageKey": null
},
v35 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "value",
  "storageKey": null
},
v36 = {
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
      (v1/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "CreateIssueQuery",
    "selections": [
      {
        "alias": null,
        "args": (v2/*: any*/),
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
                "name": "useHandleTemplateChange",
                "selections": [
                  {
                    "alias": null,
                    "args": (v3/*: any*/),
                    "concreteType": "IssueTemplate",
                    "kind": "LinkedField",
                    "name": "issueTemplate",
                    "plural": false,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "useHandleTemplateChangeIssueTemplate",
                        "selections": [
                          (v4/*: any*/),
                          (v5/*: any*/),
                          (v6/*: any*/),
                          (v7/*: any*/),
                          (v8/*: any*/),
                          (v16/*: any*/),
                          (v22/*: any*/),
                          (v24/*: any*/),
                          (v25/*: any*/)
                        ],
                        "args": null,
                        "argumentDefinitions": []
                      }
                    ],
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": (v3/*: any*/),
                    "concreteType": "IssueForm",
                    "kind": "LinkedField",
                    "name": "issueForm",
                    "plural": false,
                    "selections": [
                      {
                        "kind": "InlineDataFragmentSpread",
                        "name": "useHandleTemplateChangeIssueForm",
                        "selections": [
                          (v4/*: any*/),
                          (v5/*: any*/),
                          (v6/*: any*/),
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
                                  (v4/*: any*/),
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
                          (v16/*: any*/),
                          (v22/*: any*/),
                          {
                            "alias": null,
                            "args": (v26/*: any*/),
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
                                        "selections": (v27/*: any*/),
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
                          (v24/*: any*/),
                          (v25/*: any*/)
                        ],
                        "args": null,
                        "argumentDefinitions": []
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "args": (v3/*: any*/),
                "argumentDefinitions": [
                  {
                    "defaultValue": "",
                    "kind": "LocalArgument",
                    "name": "filename"
                  }
                ]
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
    "argumentDefinitions": [
      (v1/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "CreateIssueQuery",
    "selections": [
      {
        "alias": null,
        "args": (v2/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v4/*: any*/),
          (v11/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "IssueTemplate",
                "kind": "LinkedField",
                "name": "issueTemplate",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v5/*: any*/),
                  (v6/*: any*/),
                  (v7/*: any*/),
                  (v8/*: any*/),
                  (v28/*: any*/),
                  (v29/*: any*/),
                  (v30/*: any*/),
                  (v25/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": (v3/*: any*/),
                "concreteType": "IssueForm",
                "kind": "LinkedField",
                "name": "issueForm",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  (v5/*: any*/),
                  (v6/*: any*/),
                  (v8/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "elements",
                    "plural": true,
                    "selections": [
                      (v4/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v31/*: any*/),
                          (v32/*: any*/),
                          (v33/*: any*/),
                          (v34/*: any*/),
                          (v35/*: any*/),
                          (v36/*: any*/),
                          (v25/*: any*/)
                        ],
                        "type": "IssueFormElementInput",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v31/*: any*/),
                          (v32/*: any*/),
                          (v33/*: any*/),
                          (v34/*: any*/),
                          (v35/*: any*/),
                          (v36/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "render",
                            "storageKey": null
                          },
                          (v25/*: any*/)
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
                          (v32/*: any*/),
                          (v33/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "options",
                            "storageKey": null
                          },
                          (v36/*: any*/),
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
                          (v25/*: any*/)
                        ],
                        "type": "IssueFormElementDropdown",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v32/*: any*/),
                          (v33/*: any*/),
                          {
                            "alias": "checkboxOptions",
                            "args": null,
                            "concreteType": "IssueFormElementCheckboxOption",
                            "kind": "LinkedField",
                            "name": "options",
                            "plural": true,
                            "selections": [
                              (v32/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "labelHTML",
                                "storageKey": null
                              },
                              (v36/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v25/*: any*/)
                        ],
                        "type": "IssueFormElementCheckboxes",
                        "abstractKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v28/*: any*/),
                  (v29/*: any*/),
                  {
                    "alias": null,
                    "args": (v26/*: any*/),
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
                            "selections": (v27/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "projects(first:20)"
                  },
                  (v30/*: any*/),
                  (v25/*: any*/)
                ],
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
    "id": "4ffbcb331b611999ef714eedde0b3d0b",
    "metadata": {},
    "name": "CreateIssueQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a07055edea10e255144aa55d8c188972";

export default node;
