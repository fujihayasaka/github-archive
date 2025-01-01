/**
 * @generated SignedSource<<3c13074b0b69ff061614cc5dcc335979>>
 * @relayHash 289c96706bbdaa3e1ac7055cabe08b1f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 289c96706bbdaa3e1ac7055cabe08b1f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DuplicateIssueDialogTestQuery$variables = Record<PropertyKey, never>;
export type DuplicateIssueDialogTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarPrimaryQuery">;
  } | null | undefined;
};
export type DuplicateIssueDialogTestQuery = {
  response: DuplicateIssueDialogTestQuery$data;
  variables: DuplicateIssueDialogTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "kind": "Literal",
    "name": "id",
    "value": "test-id"
  }
],
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
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
  "name": "number",
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
  "name": "login",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v7 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v8 = [
  (v2/*: any*/)
],
v9 = {
  "kind": "InlineFragment",
  "selections": (v8/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
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
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
},
v16 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  },
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "ASC",
      "field": "NAME"
    }
  }
],
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v19 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "endCursor",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasNextPage",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v21 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v22 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v23 = {
  "alias": null,
  "args": (v7/*: any*/),
  "concreteType": "ProjectV2ItemConnection",
  "kind": "LinkedField",
  "name": "projectItemsNext",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "ProjectV2ItemEdge",
      "kind": "LinkedField",
      "name": "edges",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "ProjectV2Item",
          "kind": "LinkedField",
          "name": "node",
          "plural": false,
          "selections": [
            (v2/*: any*/),
            (v6/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v2/*: any*/),
                (v10/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v20/*: any*/),
                (v12/*: any*/),
                {
                  "alias": null,
                  "args": (v21/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v1/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v2/*: any*/),
                        (v4/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v2/*: any*/),
                            (v22/*: any*/),
                            (v4/*: any*/),
                            (v17/*: any*/),
                            (v14/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v13/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v9/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v11/*: any*/),
                (v3/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v1/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v21/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v1/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v2/*: any*/),
                    (v22/*: any*/),
                    (v4/*: any*/),
                    (v17/*: any*/),
                    (v14/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v9/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v1/*: any*/)
          ],
          "storageKey": null
        },
        (v18/*: any*/)
      ],
      "storageKey": null
    },
    (v19/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v24 = {
  "alias": null,
  "args": (v7/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v25 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v26 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v27 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v28 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v29 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v31 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v32 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v33 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v34 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v35 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v36 = {
  "enumValues": (v31/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "ProjectV2SingleSelectFieldOptionColor"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "DuplicateIssueDialogTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
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
                "name": "IssueSidebarPrimaryQuery"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "DuplicateIssueDialogTestQuery",
    "selections": [
      {
        "alias": null,
        "args": (v0/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v1/*: any*/),
          (v2/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v3/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v1/*: any*/),
                      (v5/*: any*/),
                      (v2/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v6/*: any*/),
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
                  (v2/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "visibility",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": [
                      {
                        "kind": "Literal",
                        "name": "first",
                        "value": 3
                      }
                    ],
                    "concreteType": "PinnedIssueConnection",
                    "kind": "LinkedField",
                    "name": "pinnedIssues",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "totalCount",
                        "storageKey": null
                      }
                    ],
                    "storageKey": "pinnedIssues(first:3)"
                  },
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "viewerCanPinIssues",
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
                    "args": (v7/*: any*/),
                    "concreteType": "IssueTypeConnection",
                    "kind": "LinkedField",
                    "name": "issueTypes",
                    "plural": false,
                    "selections": [
                      {
                        "alias": null,
                        "args": null,
                        "concreteType": "IssueTypeEdge",
                        "kind": "LinkedField",
                        "name": "edges",
                        "plural": true,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "IssueType",
                            "kind": "LinkedField",
                            "name": "node",
                            "plural": false,
                            "selections": (v8/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": "issueTypes(first:10)"
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 20
                  }
                ],
                "concreteType": "AssigneeConnection",
                "kind": "LinkedField",
                "name": "assignedActors",
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
                      (v1/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          (v2/*: any*/),
                          (v5/*: any*/),
                          (v4/*: any*/),
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
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "assignedActors(first:20)"
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanUpdateNext",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanAssign",
                "storageKey": null
              },
              (v10/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "body",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanLabel",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Milestone",
                "kind": "LinkedField",
                "name": "milestone",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v10/*: any*/),
                  (v11/*: any*/),
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
                  (v12/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "closedAt",
                    "storageKey": null
                  }
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanSetMilestone",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "isPinned",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "locked",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanDelete",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanTransfer",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanConvertToDiscussion",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanLock",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueType",
                "kind": "LinkedField",
                "name": "issueType",
                "plural": false,
                "selections": [
                  (v2/*: any*/),
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "isEnabled",
                    "storageKey": null
                  },
                  (v13/*: any*/),
                  (v14/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "viewerCanType",
                "storageKey": null
              },
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 25
                  }
                ],
                "concreteType": "IssueFieldValueConnection",
                "kind": "LinkedField",
                "name": "issueFieldValues",
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
                      (v1/*: any*/),
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "field",
                            "plural": false,
                            "selections": [
                              (v1/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v2/*: any*/),
                                  (v4/*: any*/),
                                  (v15/*: any*/)
                                ],
                                "type": "IssueFieldText",
                                "abstractKey": null
                              },
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          },
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "value",
                            "storageKey": null
                          }
                        ],
                        "type": "IssueFieldTextValue",
                        "abstractKey": null
                      },
                      {
                        "kind": "InlineFragment",
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": null,
                            "kind": "LinkedField",
                            "name": "field",
                            "plural": false,
                            "selections": [
                              (v1/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v4/*: any*/),
                                  (v15/*: any*/)
                                ],
                                "type": "IssueFieldSingleSelect",
                                "abstractKey": null
                              },
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v4/*: any*/),
                          (v14/*: any*/),
                          (v13/*: any*/)
                        ],
                        "type": "IssueFieldSingleSelectValue",
                        "abstractKey": null
                      },
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "issueFieldValues(first:25)"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v16/*: any*/),
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
                              (v2/*: any*/),
                              (v14/*: any*/),
                              (v4/*: any*/),
                              (v17/*: any*/),
                              (v13/*: any*/),
                              (v12/*: any*/),
                              (v1/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v18/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v19/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v16/*: any*/),
                    "filters": [
                      "orderBy"
                    ],
                    "handle": "connection",
                    "key": "MetadataSectionAssignedLabels_labels",
                    "kind": "LinkedHandle",
                    "name": "labels"
                  },
                  {
                    "kind": "TypeDiscriminator",
                    "abstractKey": "__isNode"
                  }
                ],
                "type": "Labelable",
                "abstractKey": "__isLabelable"
              },
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v23/*: any*/),
                      (v24/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "viewerCanUpdateMetadata",
                        "storageKey": null
                      }
                    ],
                    "type": "Issue",
                    "abstractKey": null
                  },
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v23/*: any*/),
                      (v24/*: any*/),
                      (v20/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              }
            ],
            "type": "Issue",
            "abstractKey": null
          }
        ],
        "storageKey": "node(id:\"test-id\")"
      }
    ]
  },
  "params": {
    "id": "289c96706bbdaa3e1ac7055cabe08b1f",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isIssueOrPullRequest": (v25/*: any*/),
        "node.__isLabelable": (v25/*: any*/),
        "node.__isNode": (v25/*: any*/),
        "node.__typename": (v25/*: any*/),
        "node.assignedActors": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "AssigneeConnection"
        },
        "node.assignedActors.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "Assignee"
        },
        "node.assignedActors.nodes.__isActor": (v25/*: any*/),
        "node.assignedActors.nodes.__isNode": (v25/*: any*/),
        "node.assignedActors.nodes.__typename": (v25/*: any*/),
        "node.assignedActors.nodes.avatarUrl": (v26/*: any*/),
        "node.assignedActors.nodes.id": (v27/*: any*/),
        "node.assignedActors.nodes.isCopilot": (v28/*: any*/),
        "node.assignedActors.nodes.login": (v25/*: any*/),
        "node.assignedActors.nodes.name": (v29/*: any*/),
        "node.assignedActors.nodes.profileResourcePath": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "URI"
        },
        "node.body": (v25/*: any*/),
        "node.id": (v27/*: any*/),
        "node.isPinned": (v30/*: any*/),
        "node.issueFieldValues": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFieldValueConnection"
        },
        "node.issueFieldValues.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueFieldValue"
        },
        "node.issueFieldValues.nodes.__isNode": (v25/*: any*/),
        "node.issueFieldValues.nodes.__typename": (v25/*: any*/),
        "node.issueFieldValues.nodes.color": {
          "enumValues": (v31/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueFieldSingleSelectOptionColor"
        },
        "node.issueFieldValues.nodes.description": (v29/*: any*/),
        "node.issueFieldValues.nodes.field": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFields"
        },
        "node.issueFieldValues.nodes.field.__isNode": (v25/*: any*/),
        "node.issueFieldValues.nodes.field.__typename": (v25/*: any*/),
        "node.issueFieldValues.nodes.field.dataType": {
          "enumValues": [
            "SINGLE_SELECT",
            "TEXT"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueFieldDataType"
        },
        "node.issueFieldValues.nodes.field.id": (v27/*: any*/),
        "node.issueFieldValues.nodes.field.name": (v25/*: any*/),
        "node.issueFieldValues.nodes.id": (v27/*: any*/),
        "node.issueFieldValues.nodes.name": (v25/*: any*/),
        "node.issueFieldValues.nodes.value": (v25/*: any*/),
        "node.issueType": (v32/*: any*/),
        "node.issueType.color": {
          "enumValues": (v31/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueTypeColor"
        },
        "node.issueType.description": (v29/*: any*/),
        "node.issueType.id": (v27/*: any*/),
        "node.issueType.isEnabled": (v28/*: any*/),
        "node.issueType.name": (v25/*: any*/),
        "node.labels": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "LabelConnection"
        },
        "node.labels.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "LabelEdge"
        },
        "node.labels.edges.cursor": (v25/*: any*/),
        "node.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "node.labels.edges.node.__typename": (v25/*: any*/),
        "node.labels.edges.node.color": (v25/*: any*/),
        "node.labels.edges.node.description": (v29/*: any*/),
        "node.labels.edges.node.id": (v27/*: any*/),
        "node.labels.edges.node.name": (v25/*: any*/),
        "node.labels.edges.node.nameHTML": (v25/*: any*/),
        "node.labels.edges.node.url": (v26/*: any*/),
        "node.labels.pageInfo": (v33/*: any*/),
        "node.labels.pageInfo.endCursor": (v29/*: any*/),
        "node.labels.pageInfo.hasNextPage": (v28/*: any*/),
        "node.locked": (v28/*: any*/),
        "node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestone.closed": (v28/*: any*/),
        "node.milestone.closedAt": (v34/*: any*/),
        "node.milestone.dueOn": (v34/*: any*/),
        "node.milestone.id": (v27/*: any*/),
        "node.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "node.milestone.title": (v25/*: any*/),
        "node.milestone.url": (v26/*: any*/),
        "node.number": (v35/*: any*/),
        "node.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "node.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "node.projectItemsNext.edges.cursor": (v25/*: any*/),
        "node.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "node.projectItemsNext.edges.node.__typename": (v25/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "node.projectItemsNext.edges.node.fieldValueByName.__isNode": (v25/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.__typename": (v25/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.color": (v36/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.id": (v27/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.name": (v29/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v29/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.optionId": (v29/*: any*/),
        "node.projectItemsNext.edges.node.id": (v27/*: any*/),
        "node.projectItemsNext.edges.node.isArchived": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.projectItemsNext.edges.node.project.__typename": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.closed": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "node.projectItemsNext.edges.node.project.field.__isNode": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.__typename": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.id": (v27/*: any*/),
        "node.projectItemsNext.edges.node.project.field.name": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "node.projectItemsNext.edges.node.project.field.options.color": (v36/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.description": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.id": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.name": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.nameHTML": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.optionId": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.id": (v27/*: any*/),
        "node.projectItemsNext.edges.node.project.number": (v35/*: any*/),
        "node.projectItemsNext.edges.node.project.template": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.title": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.url": (v26/*: any*/),
        "node.projectItemsNext.edges.node.project.viewerCanUpdate": (v28/*: any*/),
        "node.projectItemsNext.pageInfo": (v33/*: any*/),
        "node.projectItemsNext.pageInfo.endCursor": (v29/*: any*/),
        "node.projectItemsNext.pageInfo.hasNextPage": (v28/*: any*/),
        "node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.repository.id": (v27/*: any*/),
        "node.repository.isArchived": (v28/*: any*/),
        "node.repository.issueTypes": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "IssueTypeConnection"
        },
        "node.repository.issueTypes.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueTypeEdge"
        },
        "node.repository.issueTypes.edges.node": (v32/*: any*/),
        "node.repository.issueTypes.edges.node.id": (v27/*: any*/),
        "node.repository.name": (v25/*: any*/),
        "node.repository.nameWithOwner": (v25/*: any*/),
        "node.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "node.repository.owner.__typename": (v25/*: any*/),
        "node.repository.owner.id": (v27/*: any*/),
        "node.repository.owner.login": (v25/*: any*/),
        "node.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "node.repository.pinnedIssues.totalCount": (v35/*: any*/),
        "node.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "node.repository.planFeatures.maximumAssignees": (v35/*: any*/),
        "node.repository.viewerCanPinIssues": (v28/*: any*/),
        "node.repository.visibility": {
          "enumValues": [
            "INTERNAL",
            "PRIVATE",
            "PUBLIC"
          ],
          "nullable": false,
          "plural": false,
          "type": "RepositoryVisibility"
        },
        "node.title": (v25/*: any*/),
        "node.viewerCanAssign": (v28/*: any*/),
        "node.viewerCanConvertToDiscussion": (v30/*: any*/),
        "node.viewerCanDelete": (v28/*: any*/),
        "node.viewerCanLabel": (v28/*: any*/),
        "node.viewerCanLock": (v30/*: any*/),
        "node.viewerCanSetMilestone": (v28/*: any*/),
        "node.viewerCanTransfer": (v28/*: any*/),
        "node.viewerCanType": (v30/*: any*/),
        "node.viewerCanUpdate": (v28/*: any*/),
        "node.viewerCanUpdateMetadata": (v30/*: any*/),
        "node.viewerCanUpdateNext": (v30/*: any*/)
      }
    },
    "name": "DuplicateIssueDialogTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "d5cf4ba4131831ed6cf6f2b06c85aa17";

export default node;
