/**
 * @generated SignedSource<<ab0d1334b9a198381af156b439c51cc2>>
 * @relayHash 6f3d18d75a16d0e0bf321921cf5e4214
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 6f3d18d75a16d0e0bf321921cf5e4214

import { ConcreteRequest } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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
v15 = [
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
v16 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v17 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v18 = {
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
v19 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v20 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v21 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v22 = {
  "kind": "InlineFragment",
  "selections": (v8/*: any*/),
  "type": "Node",
  "abstractKey": "__isNode"
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
                (v19/*: any*/),
                (v12/*: any*/),
                {
                  "alias": null,
                  "args": (v20/*: any*/),
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
                            (v21/*: any*/),
                            (v4/*: any*/),
                            (v16/*: any*/),
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
                    (v22/*: any*/)
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
              "args": (v20/*: any*/),
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
                    (v21/*: any*/),
                    (v4/*: any*/),
                    (v16/*: any*/),
                    (v14/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v22/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v1/*: any*/)
          ],
          "storageKey": null
        },
        (v17/*: any*/)
      ],
      "storageKey": null
    },
    (v18/*: any*/)
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
  "nullable": true,
  "plural": false,
  "type": "String"
},
v29 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "Boolean"
},
v30 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "IssueType"
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
  "nullable": false,
  "plural": false,
  "type": "Boolean"
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
                    "name": "isPrivate",
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
                "concreteType": "UserConnection",
                "kind": "LinkedField",
                "name": "assignees",
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
                      (v2/*: any*/),
                      (v5/*: any*/),
                      (v4/*: any*/),
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "assignees(first:20)"
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
                "kind": "InlineFragment",
                "selections": [
                  {
                    "alias": null,
                    "args": (v15/*: any*/),
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
                              (v16/*: any*/),
                              (v13/*: any*/),
                              (v12/*: any*/),
                              (v1/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v17/*: any*/)
                        ],
                        "storageKey": null
                      },
                      (v18/*: any*/)
                    ],
                    "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
                  },
                  {
                    "alias": null,
                    "args": (v15/*: any*/),
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
                      (v19/*: any*/)
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
          (v9/*: any*/),
          (v4/*: any*/),
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "isEmployee",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "6f3d18d75a16d0e0bf321921cf5e4214",
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
        "node.assignees": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "UserConnection"
        },
        "node.assignees.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "User"
        },
        "node.assignees.nodes.avatarUrl": (v26/*: any*/),
        "node.assignees.nodes.id": (v27/*: any*/),
        "node.assignees.nodes.login": (v25/*: any*/),
        "node.assignees.nodes.name": (v28/*: any*/),
        "node.id": (v27/*: any*/),
        "node.isPinned": (v29/*: any*/),
        "node.issueType": (v30/*: any*/),
        "node.issueType.color": {
          "enumValues": (v31/*: any*/),
          "nullable": false,
          "plural": false,
          "type": "IssueTypeColor"
        },
        "node.issueType.description": (v28/*: any*/),
        "node.issueType.id": (v27/*: any*/),
        "node.issueType.isEnabled": (v32/*: any*/),
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
        "node.labels.edges.node.description": (v28/*: any*/),
        "node.labels.edges.node.id": (v27/*: any*/),
        "node.labels.edges.node.name": (v25/*: any*/),
        "node.labels.edges.node.nameHTML": (v25/*: any*/),
        "node.labels.edges.node.url": (v26/*: any*/),
        "node.labels.pageInfo": (v33/*: any*/),
        "node.labels.pageInfo.endCursor": (v28/*: any*/),
        "node.labels.pageInfo.hasNextPage": (v32/*: any*/),
        "node.locked": (v32/*: any*/),
        "node.milestone": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Milestone"
        },
        "node.milestone.closed": (v32/*: any*/),
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
        "node.projectItemsNext.edges.node.fieldValueByName.name": (v28/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v28/*: any*/),
        "node.projectItemsNext.edges.node.fieldValueByName.optionId": (v28/*: any*/),
        "node.projectItemsNext.edges.node.id": (v27/*: any*/),
        "node.projectItemsNext.edges.node.isArchived": (v32/*: any*/),
        "node.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "node.projectItemsNext.edges.node.project.__typename": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.closed": (v32/*: any*/),
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
        "node.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v32/*: any*/),
        "node.projectItemsNext.edges.node.project.id": (v27/*: any*/),
        "node.projectItemsNext.edges.node.project.number": (v35/*: any*/),
        "node.projectItemsNext.edges.node.project.template": (v32/*: any*/),
        "node.projectItemsNext.edges.node.project.title": (v25/*: any*/),
        "node.projectItemsNext.edges.node.project.url": (v26/*: any*/),
        "node.projectItemsNext.edges.node.project.viewerCanUpdate": (v32/*: any*/),
        "node.projectItemsNext.pageInfo": (v33/*: any*/),
        "node.projectItemsNext.pageInfo.endCursor": (v28/*: any*/),
        "node.projectItemsNext.pageInfo.hasNextPage": (v32/*: any*/),
        "node.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "node.repository.id": (v27/*: any*/),
        "node.repository.isArchived": (v32/*: any*/),
        "node.repository.isPrivate": (v32/*: any*/),
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
        "node.repository.issueTypes.edges.node": (v30/*: any*/),
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
        "node.repository.viewerCanPinIssues": (v32/*: any*/),
        "node.viewerCanAssign": (v32/*: any*/),
        "node.viewerCanConvertToDiscussion": (v29/*: any*/),
        "node.viewerCanDelete": (v32/*: any*/),
        "node.viewerCanLabel": (v32/*: any*/),
        "node.viewerCanLock": (v29/*: any*/),
        "node.viewerCanSetMilestone": (v32/*: any*/),
        "node.viewerCanTransfer": (v32/*: any*/),
        "node.viewerCanType": (v29/*: any*/),
        "node.viewerCanUpdate": (v32/*: any*/),
        "node.viewerCanUpdateMetadata": (v29/*: any*/),
        "node.viewerCanUpdateNext": (v29/*: any*/),
        "viewer": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "User"
        },
        "viewer.avatarUrl": (v26/*: any*/),
        "viewer.enterpriseManagedEnterpriseId": (v28/*: any*/),
        "viewer.id": (v27/*: any*/),
        "viewer.isEmployee": (v32/*: any*/),
        "viewer.isEnterpriseManagedUser": (v29/*: any*/),
        "viewer.login": (v25/*: any*/),
        "viewer.name": (v28/*: any*/)
      }
    },
    "name": "IssueSidebarTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "85f15083026e42df551edf7e947bc136";

export default node;
