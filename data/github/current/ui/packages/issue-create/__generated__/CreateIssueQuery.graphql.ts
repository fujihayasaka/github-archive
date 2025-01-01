/**
 * @generated SignedSource<<c4f1fc49e8d697ebc3d2d9a4cd2dc9fe>>
 * @relayHash f6d7d35a649017a82d6174fa4caefc3a
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID f6d7d35a649017a82d6174fa4caefc3a

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
v18 = [
  (v11/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
    "storageKey": null
  },
  (v5/*: any*/),
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
v19 = {
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
              "selections": (v18/*: any*/),
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
v20 = [
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
v21 = {
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
      "selections": (v20/*: any*/),
      "args": null,
      "argumentDefinitions": ([]/*: any*/)
    }
  ],
  "storageKey": null
},
v22 = {
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
v23 = [
  (v9/*: any*/)
],
v24 = [
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
v25 = {
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
v26 = {
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
          "selections": (v18/*: any*/),
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "storageKey": "assignees(first:10)"
},
v27 = {
  "alias": null,
  "args": null,
  "concreteType": "IssueType",
  "kind": "LinkedField",
  "name": "type",
  "plural": false,
  "selections": (v20/*: any*/),
  "storageKey": null
},
v28 = {
  "alias": "itemId",
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v29 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "label",
  "storageKey": null
},
v30 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "descriptionHTML",
  "storageKey": null
},
v31 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "placeholder",
  "storageKey": null
},
v32 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "value",
  "storageKey": null
},
v33 = {
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
                          (v19/*: any*/),
                          (v21/*: any*/),
                          (v22/*: any*/)
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
                          (v19/*: any*/),
                          {
                            "alias": null,
                            "args": (v23/*: any*/),
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
                                        "selections": (v24/*: any*/),
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
                          (v21/*: any*/),
                          (v22/*: any*/)
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
                  (v25/*: any*/),
                  (v26/*: any*/),
                  (v27/*: any*/),
                  (v22/*: any*/)
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
                          (v28/*: any*/),
                          (v29/*: any*/),
                          (v30/*: any*/),
                          (v31/*: any*/),
                          (v32/*: any*/),
                          (v33/*: any*/),
                          (v22/*: any*/)
                        ],
                        "type": "IssueFormElementInput",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v28/*: any*/),
                          (v29/*: any*/),
                          (v30/*: any*/),
                          (v31/*: any*/),
                          (v32/*: any*/),
                          (v33/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "render",
                            "storageKey": null
                          },
                          (v22/*: any*/)
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
                          (v29/*: any*/),
                          (v30/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "options",
                            "storageKey": null
                          },
                          (v33/*: any*/),
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
                          (v22/*: any*/)
                        ],
                        "type": "IssueFormElementDropdown",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v29/*: any*/),
                          (v30/*: any*/),
                          {
                            "alias": "checkboxOptions",
                            "args": null,
                            "concreteType": "IssueFormElementCheckboxOption",
                            "kind": "LinkedField",
                            "name": "options",
                            "plural": true,
                            "selections": [
                              (v29/*: any*/),
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "labelHTML",
                                "storageKey": null
                              },
                              (v33/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v22/*: any*/)
                        ],
                        "type": "IssueFormElementCheckboxes",
                        "abstractKey": null
                      }
                    ],
                    "storageKey": null
                  },
                  (v25/*: any*/),
                  (v26/*: any*/),
                  {
                    "alias": null,
                    "args": (v23/*: any*/),
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
                            "selections": (v24/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "projects(first:20)"
                  },
                  (v27/*: any*/),
                  (v22/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "type": "Repository",
            "abstractKey": null
          },
          (v11/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "f6d7d35a649017a82d6174fa4caefc3a",
    "metadata": {},
    "name": "CreateIssueQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "cb09c336bdc691d8eb1e3f9f631f7c21";

export default node;
