/**
 * @generated SignedSource<<dfb78e0a9a1e0bae3e4bc4a154f62dfb>>
 * @relayHash 93b63c40b38c774d3d6d4cf6e63444b7
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 93b63c40b38c774d3d6d4cf6e63444b7

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AddToProjectsActionTestSubscription$variables = {
  issueId: string;
};
export type AddToProjectsActionTestSubscription$data = {
  readonly issueUpdated: {
    readonly issueMetadataUpdated: {
      readonly " $fragmentSpreads": FragmentRefs<"ProjectsSectionFragment">;
    } | null | undefined;
  };
};
export type AddToProjectsActionTestSubscription = {
  response: AddToProjectsActionTestSubscription$data;
  variables: AddToProjectsActionTestSubscription$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "issueId"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "issueId"
  }
],
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
  "name": "__typename",
  "storageKey": null
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "isArchived",
  "storageKey": null
},
v7 = {
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
        (v5/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "login",
          "storageKey": null
        },
        (v2/*: any*/)
      ],
      "storageKey": null
    },
    (v6/*: any*/),
    (v2/*: any*/)
  ],
  "storageKey": null
},
v8 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v10 = [
  {
    "kind": "Literal",
    "name": "name",
    "value": "Status"
  }
],
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "optionId",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "nameHTML",
  "storageKey": null
},
v13 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v14 = {
  "kind": "InlineFragment",
  "selections": [
    (v2/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v15 = {
  "alias": null,
  "args": (v8/*: any*/),
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
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "title",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "template",
                  "storageKey": null
                },
                (v9/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "url",
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": (v10/*: any*/),
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    (v5/*: any*/),
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
                            (v11/*: any*/),
                            (v4/*: any*/),
                            (v12/*: any*/),
                            (v13/*: any*/),
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "descriptionHTML",
                              "storageKey": null
                            },
                            {
                              "alias": null,
                              "args": null,
                              "kind": "ScalarField",
                              "name": "description",
                              "storageKey": null
                            }
                          ],
                          "storageKey": null
                        }
                      ],
                      "type": "ProjectV2SingleSelectField",
                      "abstractKey": null
                    },
                    (v14/*: any*/)
                  ],
                  "storageKey": "field(name:\"Status\")"
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "closed",
                  "storageKey": null
                },
                (v3/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v5/*: any*/)
              ],
              "storageKey": null
            },
            {
              "alias": null,
              "args": (v10/*: any*/),
              "concreteType": null,
              "kind": "LinkedField",
              "name": "fieldValueByName",
              "plural": false,
              "selections": [
                (v5/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v2/*: any*/),
                    (v11/*: any*/),
                    (v4/*: any*/),
                    (v12/*: any*/),
                    (v13/*: any*/)
                  ],
                  "type": "ProjectV2ItemFieldSingleSelectValue",
                  "abstractKey": null
                },
                (v14/*: any*/)
              ],
              "storageKey": "fieldValueByName(name:\"Status\")"
            },
            (v5/*: any*/)
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "cursor",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
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
    }
  ],
  "storageKey": "projectItemsNext(first:10)"
},
v16 = {
  "alias": null,
  "args": (v8/*: any*/),
  "filters": [
    "allowedOwner"
  ],
  "handle": "connection",
  "key": "ProjectSection_projectItemsNext",
  "kind": "LinkedHandle",
  "name": "projectItemsNext"
},
v17 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
},
v18 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v19 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Int"
},
v20 = {
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
  "type": "ProjectV2SingleSelectFieldOptionColor"
},
v21 = {
  "enumValues": null,
  "nullable": true,
  "plural": false,
  "type": "String"
},
v22 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "Boolean"
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "AddToProjectsActionTestSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "ProjectsSectionFragment"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "EventSubscription",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "AddToProjectsActionTestSubscription",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "IssueUpdatedPayload",
        "kind": "LinkedField",
        "name": "issueUpdated",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issueMetadataUpdated",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": [
                  {
                    "kind": "InlineFragment",
                    "selections": [
                      (v3/*: any*/),
                      (v7/*: any*/),
                      (v15/*: any*/),
                      (v16/*: any*/),
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
                      (v3/*: any*/),
                      (v7/*: any*/),
                      (v15/*: any*/),
                      (v16/*: any*/),
                      (v9/*: any*/)
                    ],
                    "type": "PullRequest",
                    "abstractKey": null
                  }
                ],
                "type": "IssueOrPullRequest",
                "abstractKey": "__isIssueOrPullRequest"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "93b63c40b38c774d3d6d4cf6e63444b7",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issueUpdated": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueUpdatedPayload"
        },
        "issueUpdated.issueMetadataUpdated": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "issueUpdated.issueMetadataUpdated.__isIssueOrPullRequest": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.number": (v19/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.cursor": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.__typename": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.__isNode": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.__typename": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.color": (v20/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.name": (v21/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v21/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.fieldValueByName.optionId": (v21/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.isArchived": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.__typename": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.closed": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.__isNode": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.__typename": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.name": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.color": (v20/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.description": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.id": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.name": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.nameHTML": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.field.options.optionId": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.number": (v19/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.template": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.title": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.edges.node.project.viewerCanUpdate": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "issueUpdated.issueMetadataUpdated.projectItemsNext.pageInfo.endCursor": (v21/*: any*/),
        "issueUpdated.issueMetadataUpdated.projectItemsNext.pageInfo.hasNextPage": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "issueUpdated.issueMetadataUpdated.repository.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.isArchived": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.name": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issueUpdated.issueMetadataUpdated.repository.owner.__typename": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner.id": (v18/*: any*/),
        "issueUpdated.issueMetadataUpdated.repository.owner.login": (v17/*: any*/),
        "issueUpdated.issueMetadataUpdated.viewerCanUpdate": (v22/*: any*/),
        "issueUpdated.issueMetadataUpdated.viewerCanUpdateMetadata": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "AddToProjectsActionTestSubscription",
    "operationKind": "subscription",
    "text": null
  }
};
})();

(node as any).hash = "605ff50eaaafa85898925cc606e3a205";

export default node;
