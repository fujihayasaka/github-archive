/**
 * @generated SignedSource<<b5b2c08cfe26a0291a722329f43020d4>>
 * @relayHash 48b046770f29ec975d344f0c739afc1d
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 48b046770f29ec975d344f0c739afc1d

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarTestQuery$variables = Record<PropertyKey, never>;
export type IssueSidebarTestQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarPrimaryQuery">;
  } | null | undefined;
  readonly viewer: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueViewerViewer">;
  };
};
export type IssueSidebarTestQuery = {
  response: IssueSidebarTestQuery$data;
  variables: IssueSidebarTestQuery$variables;
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
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "profileResourcePath",
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
v12 = {
  "kind": "InlineFragment",
  "selections": (v8/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v14 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v15 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v18 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
},
v19 = [
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
v20 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v22 = {
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
v23 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v24 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v25 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v26 = {
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
                (v13/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v23/*: any*/),
                (v15/*: any*/),
                {
                  "alias": null,
                  "args": (v24/*: any*/),
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
                            (v25/*: any*/),
                            (v4/*: any*/),
                            (v20/*: any*/),
                            (v17/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            (v16/*: any*/)
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v12/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                (v14/*: any*/),
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
              "args": (v24/*: any*/),
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
                    (v25/*: any*/),
                    (v4/*: any*/),
                    (v20/*: any*/),
                    (v17/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v12/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v1/*: any*/)
          ],
          "storageKey": null
        },
        (v21/*: any*/)
      ],
      "storageKey": null
    },
    (v22/*: any*/)
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v27 = {
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
v28 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v29 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "URI"
},
v30 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v31 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
},
v32 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v33 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "URI"
},
v34 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v35 = [
  "BLUE",
  "GRAY",
  "GREEN",
  "ORANGE",
  "PINK",
  "PURPLE",
  "RED",
  "YELLOW"
],
v36 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
},
v37 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "PageInfo"
},
v38 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "DateTime"
},
v39 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v40 = {
  "enumValues": (v35/*: any*/),
  "nullable": false,
  "plural": false,
  "type": "ProjectV2SingleSelectFieldOptionColor"
};
return {
  "fragment": {
    "argumentDefinitions": [],
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueSidebarTestQuery",
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
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "IssueViewerViewer"
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
    "argumentDefinitions": [],
    "kind": "Operation",
    "name": "IssueSidebarTestQuery",
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
                          (v9/*: any*/),
                          (v10/*: any*/),
                          (v11/*: any*/)
                        ],
                        "type": "Actor",
                        "abstractKey": "__isActor"
                      },
                      (v12/*: any*/)
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
              (v13/*: any*/),
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
                  (v13/*: any*/),
                  (v14/*: any*/),
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
                  (v15/*: any*/),
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
                  (v16/*: any*/),
                  (v17/*: any*/)
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
                                  (v18/*: any*/)
                                ],
                                "type": "IssueFieldText",
                                "abstractKey": null
                              },
                              (v12/*: any*/)
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
                                  (v18/*: any*/)
                                ],
                                "type": "IssueFieldSingleSelect",
                                "abstractKey": null
                              },
                              (v12/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v4/*: any*/),
                          (v17/*: any*/),
                          (v16/*: any*/)
                        ],
                        "type": "IssueFieldSingleSelectValue",
                        "abstractKey": null
                      },
                      (v12/*: any*/)
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
                    "args": (v19/*: any*/),
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
                              (v17/*: any*/),
                              (v4/*: any*/),
                              (v20/*: any*/),
                              (v16/*: any*/),
                              (v15/*: any*/),
                              (v1/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v21/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v22/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v19/*: any*/),
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
                      (v26/*: any*/),
                      (v27/*: any*/),
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
                      (v26/*: any*/),
                      (v27/*: any*/),
                      (v23/*: any*/)
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
      },
      {
        "alias": null,
        "args": null,
        "concreteType": "User",
        "kind": "LinkedField",
        "name": "viewer",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isEnterpriseManagedUser",
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "enterpriseManagedEnterpriseId",
            "storageKey": null
          },
          (v5/*: any*/),
          (v2/*: any*/),
          (v10/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v1/*: any*/),
              (v4/*: any*/),
              (v9/*: any*/),
              (v11/*: any*/)
            ],
            "type": "Actor",
            "abstractKey": "__isActor"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "48b046770f29ec975d344f0c739afc1d",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "node.__isIssueOrPullRequest": (v28/*: any*/),
        "node.__isLabelable": (v28/*: any*/),
        "node.__isNode": (v28/*: any*/),
        "node.__typename": (v28/*: any*/),
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
        "node.assignedActors.nodes.__isActor": (v28/*: any*/),
        "node.assignedActors.nodes.__isNode": (v28/*: any*/),
        "node.assignedActors.nodes.__typename": (v28/*: any*/),
        "node.assignedActors.nodes.avatarUrl": (v29/*: any*/),
        "node.assignedActors.nodes.id": (v30/*: any*/),
        "node.assignedActors.nodes.isCopilot": (v31/*: any*/),
        "node.assignedActors.nodes.login": (v28/*: any*/),
        "node.assignedActors.nodes.name": (v32/*: any*/),
        "node.assignedActors.nodes.profileResourcePath": (v33/*: any*/),
        "node.body": (v28/*: any*/),
        "node.id": (v30/*: any*/),
        "node.isPinned": (v34/*: any*/),
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
        "node.issueFieldValues.nodes.__isNode": (v28/*: any*/),
        "node.issueFieldValues.nodes.__typename": (v28/*: any*/),
        "node.issueFieldValues.nodes.color": {
          "enumValues": (v35/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueFieldSingleSelectOptionColor"
        },
        "node.issueFieldValues.nodes.description": (v32/*: any*/),
        "node.issueFieldValues.nodes.field": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFields"
        },
        "node.issueFieldValues.nodes.field.__isNode": (v28/*: any*/),
        "node.issueFieldValues.nodes.field.__typename": (v28/*: any*/),
        "node.issueFieldValues.nodes.field.dataType": {
          "enumValues": [
            "SINGLE_SELECT",
            "TEXT"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueFieldDataType"
        },
        "node.issueFieldValues.nodes.field.id": (v30/*: any*/),
        "node.issueFieldValues.nodes.field.name": (v28/*: any*/),
        "node.issueFieldValues.nodes.id": (v30/*: any*/),
        "node.issueFieldValues.nodes.name": (v28/*: any*/),
        "node.issueFieldValues.nodes.value": (v28/*: any*/),
        "node.issueType": (v36/*: any*/),
        "node.issueType.color": {
          "enumValues": (v35/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueTypeColor"
        },
        "node.issueType.description": (v32/*: any*/),
        "node.issueType.id": (v30/*: any*/),
        "node.issueType.isEnabled": (v31/*: any*/),
        "node.issueType.name": (v28/*: any*/),
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
        "node.labels.edges.cursor": (v28/*: any*/),
        "node.labels.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Label"
        },
        "node.labels.edges.node.__typename": (v28/*: any*/),
        "node.labels.edges.node.color": (v28/*: any*/),
        "node.labels.edges.node.description": (v32/*: any*/),
        "node.labels.edges.node.id": (v30/*: any*/),
        "node.labels.edges.node.name": (v28/*: any*/),
        "node.labels.edges.node.nameHTML": (v28/*: any*/),
        "node.labels.edges.node.url": (v29/*: any*/),
        "node.labels.pageInfo": (v37/*: any*/),
        "node.labels.pageInfo.endCursor": (v32/*: any*/),
        "node.labels.pageInfo.hasNextPage": (v31/*: any*/),
        "node.locked": (v31/*: any*/),
        "node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestone.closed": (v31/*: any*/),
        "node.milestone.closedAt": (v38/*: any*/),
        "node.milestone.dueOn": (v38/*: any*/),
        "node.milestone.id": (v30/*: any*/),
        "node.milestone.progressPercentage": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Float"
        },
        "node.milestone.title": (v28/*: any*/),
        "node.milestone.url": (v29/*: any*/),
        "node.number": (v39/*: any*/),
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
        "node.projectItemsNext.edges.cursor": (v28/*: any*/),
        "node.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "node.projectItemsNext.edges.node.__typename": (v28/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "node.projectItemsNext.edges.node.fieldValueByName.__isNode": (v28/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.__typename": (v28/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.color": (v40/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.id": (v30/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.name": (v32/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v32/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.optionId": (v32/*: any*/),
        "node.projectItemsNext.edges.node.id": (v30/*: any*/),
        "node.projectItemsNext.edges.node.isArchived": (v31/*: any*/),
        "node.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.projectItemsNext.edges.node.project.__typename": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.closed": (v31/*: any*/),
        "node.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "node.projectItemsNext.edges.node.project.field.__isNode": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.__typename": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.id": (v30/*: any*/),
        "node.projectItemsNext.edges.node.project.field.name": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "node.projectItemsNext.edges.node.project.field.options.color": (v40/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.description": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.id": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.name": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.nameHTML": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.field.options.optionId": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v31/*: any*/),
        "node.projectItemsNext.edges.node.project.id": (v30/*: any*/),
        "node.projectItemsNext.edges.node.project.number": (v39/*: any*/),
        "node.projectItemsNext.edges.node.project.template": (v31/*: any*/),
        "node.projectItemsNext.edges.node.project.title": (v28/*: any*/),
        "node.projectItemsNext.edges.node.project.url": (v29/*: any*/),
        "node.projectItemsNext.edges.node.project.viewerCanUpdate": (v31/*: any*/),
        "node.projectItemsNext.pageInfo": (v37/*: any*/),
        "node.projectItemsNext.pageInfo.endCursor": (v32/*: any*/),
        "node.projectItemsNext.pageInfo.hasNextPage": (v31/*: any*/),
        "node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.repository.id": (v30/*: any*/),
        "node.repository.isArchived": (v31/*: any*/),
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
        "node.repository.issueTypes.edges.node": (v36/*: any*/),
        "node.repository.issueTypes.edges.node.id": (v30/*: any*/),
        "node.repository.name": (v28/*: any*/),
        "node.repository.nameWithOwner": (v28/*: any*/),
        "node.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "node.repository.owner.__typename": (v28/*: any*/),
        "node.repository.owner.id": (v30/*: any*/),
        "node.repository.owner.login": (v28/*: any*/),
        "node.repository.pinnedIssues": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "PinnedIssueConnection"
        },
        "node.repository.pinnedIssues.totalCount": (v39/*: any*/),
        "node.repository.planFeatures": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryPlanFeatures"
        },
        "node.repository.planFeatures.maximumAssignees": (v39/*: any*/),
        "node.repository.viewerCanPinIssues": (v31/*: any*/),
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
        "node.title": (v28/*: any*/),
        "node.viewerCanAssign": (v31/*: any*/),
        "node.viewerCanConvertToDiscussion": (v34/*: any*/),
        "node.viewerCanDelete": (v31/*: any*/),
        "node.viewerCanLabel": (v31/*: any*/),
        "node.viewerCanLock": (v34/*: any*/),
        "node.viewerCanSetMilestone": (v31/*: any*/),
        "node.viewerCanTransfer": (v31/*: any*/),
        "node.viewerCanType": (v34/*: any*/),
        "node.viewerCanUpdate": (v31/*: any*/),
        "node.viewerCanUpdateMetadata": (v34/*: any*/),
        "node.viewerCanUpdateNext": (v34/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.__isActor": (v28/*: any*/),
        "viewer.__typename": (v28/*: any*/),
        "viewer.avatarUrl": (v29/*: any*/),
        "viewer.enterpriseManagedEnterpriseId": (v32/*: any*/),
        "viewer.id": (v30/*: any*/),
        "viewer.isCopilot": (v31/*: any*/),
        "viewer.isEnterpriseManagedUser": (v34/*: any*/),
        "viewer.login": (v28/*: any*/),
        "viewer.name": (v32/*: any*/),
        "viewer.profileResourcePath": (v33/*: any*/)
      }
    },
    "name": "IssueSidebarTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "5366718aedcbdb024ded8f8d4093af77";

export default node;
