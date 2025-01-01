/**
 * @generated SignedSource<<56858e66620deed0c8e5055ebf13b9ab>>
 * @relayHash 6bbde2bbeae4e8f8fd217eb99c7cb38f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 6bbde2bbeae4e8f8fd217eb99c7cb38f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FieldsSectionStoryQuery$variables = {
  number: number;
  owner: string;
  repo: string;
};
export type FieldsSectionStoryQuery$data = {
  readonly repository: {
    readonly issue: {
      readonly " $fragmentSpreads": FragmentRefs<"FieldsSectionFragment">;
    } | null | undefined;
  } | null | undefined;
};
export type FieldsSectionStoryQuery = {
  response: FieldsSectionStoryQuery$data;
  variables: FieldsSectionStoryQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "number"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = [
  {
    "kind": "Variable",
    "name": "number",
    "variableName": "number"
  }
],
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
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
  "name": "name",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
},
v9 = {
  "kind": "InlineFragment",
  "selections": [
    (v5/*: any*/)
  ],
  "type": "Node",
  "abstractKey": "__isNode"
},
v10 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "ID"
},
v11 = {
  "enumValues": null,
  "nullable": false,
  "plural": false,
  "type": "String"
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "FieldsSectionStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "FieldsSectionFragment"
              }
            ],
            "storageKey": null
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
      (v2/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "FieldsSectionStoryQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v4/*: any*/),
            "concreteType": "Issue",
            "kind": "LinkedField",
            "name": "issue",
            "plural": false,
            "selections": [
              (v5/*: any*/),
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "repository",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v6/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "login",
                        "storageKey": null
                      },
                      (v5/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v5/*: any*/)
                ],
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
                      (v6/*: any*/),
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
                              (v6/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v5/*: any*/),
                                  (v7/*: any*/),
                                  (v8/*: any*/)
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
                              (v6/*: any*/),
                              {
                                "kind": "InlineFragment",
                                "selections": [
                                  (v7/*: any*/),
                                  (v8/*: any*/)
                                ],
                                "type": "IssueFieldSingleSelect",
                                "abstractKey": null
                              },
                              (v9/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v7/*: any*/),
                          {
                            "alias": null,
                            "args": null,
                            "kind": "ScalarField",
                            "name": "color",
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
                        "type": "IssueFieldSingleSelectValue",
                        "abstractKey": null
                      },
                      (v9/*: any*/)
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "issueFieldValues(first:25)"
              }
            ],
            "storageKey": null
          },
          (v5/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "6bbde2bbeae4e8f8fd217eb99c7cb38f",
    "metadata": {
      "relayTestingSelectionTypeInfo": {
        "repository": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Repository"
        },
        "repository.id": (v10/*: any*/),
        "repository.issue": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "Issue"
        },
        "repository.issue.id": (v10/*: any*/),
        "repository.issue.issueFieldValues": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFieldValueConnection"
        },
        "repository.issue.issueFieldValues.nodes": {
          "enumValues": null,
          "nullable": true,
          "plural": true,
          "type": "IssueFieldValue"
        },
        "repository.issue.issueFieldValues.nodes.__isNode": (v11/*: any*/),
        "repository.issue.issueFieldValues.nodes.__typename": (v11/*: any*/),
        "repository.issue.issueFieldValues.nodes.color": {
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
          "type": "IssueFieldSingleSelectOptionColor"
        },
        "repository.issue.issueFieldValues.nodes.description": {
          "enumValues": null,
          "nullable": true,
          "plural": false,
          "type": "String"
        },
        "repository.issue.issueFieldValues.nodes.field": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "IssueFields"
        },
        "repository.issue.issueFieldValues.nodes.field.__isNode": (v11/*: any*/),
        "repository.issue.issueFieldValues.nodes.field.__typename": (v11/*: any*/),
        "repository.issue.issueFieldValues.nodes.field.dataType": {
          "enumValues": [
            "SINGLE_SELECT",
            "TEXT"
          ],
          "nullable": false,
          "plural": false,
          "type": "IssueFieldDataType"
        },
        "repository.issue.issueFieldValues.nodes.field.id": (v10/*: any*/),
        "repository.issue.issueFieldValues.nodes.field.name": (v11/*: any*/),
        "repository.issue.issueFieldValues.nodes.id": (v10/*: any*/),
        "repository.issue.issueFieldValues.nodes.name": (v11/*: any*/),
        "repository.issue.issueFieldValues.nodes.value": (v11/*: any*/),
        "repository.issue.repository": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "Repository"
        },
        "repository.issue.repository.id": (v10/*: any*/),
        "repository.issue.repository.owner": {
          "enumValues": null,
          "nullable": false,
          "plural": false,
          "type": "RepositoryOwner"
        },
        "repository.issue.repository.owner.__typename": (v11/*: any*/),
        "repository.issue.repository.owner.id": (v10/*: any*/),
        "repository.issue.repository.owner.login": (v11/*: any*/)
      }
    },
    "name": "FieldsSectionStoryQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "d7e7984398ea31fb05009cbb5374c06a";

export default node;
