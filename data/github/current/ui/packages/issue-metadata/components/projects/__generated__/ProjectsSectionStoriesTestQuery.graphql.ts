/**
 * @generated SignedSource<<4c30517e16cddb45934914a20b99f99b>>
 * @relayHash 6ad0545214e988bceae4672b4e312810
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 6ad0545214e988bceae4672b4e312810

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ProjectsSectionStoriesTestQuery$variables = {
  id: string;
};
export type ProjectsSectionStoriesTestQuery$data = {
  readonly issue: {
    readonly " $fragmentSpreads": FragmentRefs<"ProjectsSectionFragment">;
  } | null | undefined;
};
export type ProjectsSectionStoriesTestQuery = {
  response: ProjectsSectionStoriesTestQuery$data;
  variables: ProjectsSectionStoriesTestQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
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
    (v5/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        (v2/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "login",
          "storageKey": null
        },
        (v3/*: any*/)
      ],
      "storageKey": null
    },
    (v6/*: any*/),
    (v3/*: any*/)
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
    (v3/*: any*/)
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
            (v3/*: any*/),
            (v6/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2",
              "kind": "LinkedField",
              "name": "project",
              "plural": false,
              "selections": [
                (v3/*: any*/),
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
                    (v2/*: any*/),
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v3/*: any*/),
                        (v5/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "concreteType": "ProjectV2SingleSelectFieldOption",
                          "kind": "LinkedField",
                          "name": "options",
                          "plural": true,
                          "selections": [
                            (v3/*: any*/),
                            (v11/*: any*/),
                            (v5/*: any*/),
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
                (v4/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "hasReachedItemsLimit",
                  "storageKey": null
                },
                (v2/*: any*/)
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
                (v2/*: any*/),
                {
                  "kind": "InlineFragment",
                  "selections": [
                    (v3/*: any*/),
                    (v11/*: any*/),
                    (v5/*: any*/),
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
            (v2/*: any*/)
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
    "name": "ProjectsSectionStoriesTestQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
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
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "ProjectsSectionStoriesTestQuery",
    "selections": [
      {
        "alias": "issue",
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": [
                  (v4/*: any*/),
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
                  (v4/*: any*/),
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
    ]
  },
  "params": {
    "id": "6ad0545214e988bceae4672b4e312810",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Node"
        },
        "issue.__isIssueOrPullRequest": (v17/*: any*/),
        "issue.__typename": (v17/*: any*/),
        "issue.id": (v18/*: any*/),
        "issue.number": (v19/*: any*/),
        "issue.projectItemsNext": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemConnection"
        },
        "issue.projectItemsNext.edges": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "ProjectV2ItemEdge"
        },
        "issue.projectItemsNext.edges.cursor": (v17/*: any*/),
        "issue.projectItemsNext.edges.node": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2Item"
        },
        "issue.projectItemsNext.edges.node.__typename": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2ItemFieldValue"
        },
        "issue.projectItemsNext.edges.node.fieldValueByName.__isNode": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.__typename": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.color": (v20/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.id": (v18/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.name": (v21/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.nameHTML": (v21/*: any*/),
        "issue.projectItemsNext.edges.node.fieldValueByName.optionId": (v21/*: any*/),
        "issue.projectItemsNext.edges.node.id": (v18/*: any*/),
        "issue.projectItemsNext.edges.node.isArchived": (v22/*: any*/),
        "issue.projectItemsNext.edges.node.project": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "ProjectV2"
        },
        "issue.projectItemsNext.edges.node.project.__typename": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.closed": (v22/*: any*/),
        "issue.projectItemsNext.edges.node.project.field": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "ProjectV2FieldConfiguration"
        },
        "issue.projectItemsNext.edges.node.project.field.__isNode": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.__typename": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.id": (v18/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.name": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options": {
          "enumValues": null,
          "nullable": false,
          "plural": true,
          "type": "ProjectV2SingleSelectFieldOption"
        },
        "issue.projectItemsNext.edges.node.project.field.options.color": (v20/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.description": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.descriptionHTML": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.id": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.name": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.nameHTML": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.field.options.optionId": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.hasReachedItemsLimit": (v22/*: any*/),
        "issue.projectItemsNext.edges.node.project.id": (v18/*: any*/),
        "issue.projectItemsNext.edges.node.project.number": (v19/*: any*/),
        "issue.projectItemsNext.edges.node.project.template": (v22/*: any*/),
        "issue.projectItemsNext.edges.node.project.title": (v17/*: any*/),
        "issue.projectItemsNext.edges.node.project.url": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "URI"
        },
        "issue.projectItemsNext.edges.node.project.viewerCanUpdate": (v22/*: any*/),
        "issue.projectItemsNext.pageInfo": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "PageInfo"
        },
        "issue.projectItemsNext.pageInfo.endCursor": (v21/*: any*/),
        "issue.projectItemsNext.pageInfo.hasNextPage": (v22/*: any*/),
        "issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "issue.repository.id": (v18/*: any*/),
        "issue.repository.isArchived": (v22/*: any*/),
        "issue.repository.name": (v17/*: any*/),
        "issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "issue.repository.owner.__typename": (v17/*: any*/),
        "issue.repository.owner.id": (v18/*: any*/),
        "issue.repository.owner.login": (v17/*: any*/),
        "issue.viewerCanUpdate": (v22/*: any*/),
        "issue.viewerCanUpdateMetadata": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Boolean"
        }
      }
    },
    "name": "ProjectsSectionStoriesTestQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "62460842665ea1b78cb43c173ccd0883";

export default node;
