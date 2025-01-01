/**
 * @generated SignedSource<<3f6aca9f8a2f5cb8391bd39d4cf48d4a>>
 * @relayHash 3d912b8c0cd194e312ffb8b34322ba92
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 3d912b8c0cd194e312ffb8b34322ba92

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useCopilotFetchIssueDataQuery$variables = {
  fetchAllLabels?: boolean | null | undefined;
  fetchAllTypes?: boolean | null | undefined;
  issueId: string;
};
export type useCopilotFetchIssueDataQuery$data = {
  readonly node: {
    readonly body?: string;
    readonly repository?: {
      readonly allLabels?: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
        } | null | undefined> | null | undefined;
      } | null | undefined;
      readonly issueTypes?: {
        readonly nodes: ReadonlyArray<{
          readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerIssueType">;
        } | null | undefined> | null | undefined;
      } | null | undefined;
    };
    readonly title?: string;
  } | null | undefined;
};
export type useCopilotFetchIssueDataQuery = {
  response: useCopilotFetchIssueDataQuery$data;
  variables: useCopilotFetchIssueDataQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "fetchAllLabels"
},
v1 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "fetchAllTypes"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "issueId"
},
v3 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "issueId"
  }
],
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "body",
  "storageKey": null
},
v5 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v6 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 10
  }
],
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "description",
  "storageKey": null
},
v10 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "color",
  "storageKey": null
},
v11 = [
  (v7/*: any*/),
  (v8/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "isEnabled",
    "storageKey": null
  },
  (v9/*: any*/),
  (v10/*: any*/)
],
v12 = [
  {
    "kind": "Literal",
    "name": "first",
    "value": 100
  }
],
v13 = [
  (v7/*: any*/),
  (v10/*: any*/),
  (v8/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameHTML",
    "storageKey": null
  },
  (v9/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "url",
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "useCopilotFetchIssueDataQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              (v4/*: any*/),
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
                    "condition": "fetchAllTypes",
                    "kind": "Condition",
                    "passingValue": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": (v6/*: any*/),
                        "concreteType": "IssueTypeConnection",
                        "kind": "LinkedField",
                        "name": "issueTypes",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "IssueType",
                            "kind": "LinkedField",
                            "name": "nodes",
                            "plural": true,
                            "selections": [
                              {
                                "kind": "InlineDataFragmentSpread",
                                "name": "IssueTypePickerIssueType",
                                "selections": (v11/*: any*/),
                                "args": null,
                                "argumentDefinitions": []
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": "issueTypes(first:10)"
                      }
                    ]
                  },
                  {
                    "condition": "fetchAllLabels",
                    "kind": "Condition",
                    "passingValue": true,
                    "selections": [
                      {
                        "alias": "allLabels",
                        "args": (v12/*: any*/),
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
                            "selections": [
                              {
                                "kind": "InlineDataFragmentSpread",
                                "name": "LabelPickerLabel",
                                "selections": (v13/*: any*/),
                                "args": null,
                                "argumentDefinitions": []
                              }
                            ],
                            "storageKey": null
                          }
                        ],
                        "storageKey": "labels(first:100)"
                      }
                    ]
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "Issue",
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
      (v2/*: any*/),
      (v1/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "useCopilotFetchIssueDataQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          {
            "kind": "InlineFragment",
            "selections": [
              (v4/*: any*/),
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
                    "condition": "fetchAllTypes",
                    "kind": "Condition",
                    "passingValue": true,
                    "selections": [
                      {
                        "alias": null,
                        "args": (v6/*: any*/),
                        "concreteType": "IssueTypeConnection",
                        "kind": "LinkedField",
                        "name": "issueTypes",
                        "plural": false,
                        "selections": [
                          {
                            "alias": null,
                            "args": null,
                            "concreteType": "IssueType",
                            "kind": "LinkedField",
                            "name": "nodes",
                            "plural": true,
                            "selections": (v11/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": "issueTypes(first:10)"
                      }
                    ]
                  },
                  {
                    "condition": "fetchAllLabels",
                    "kind": "Condition",
                    "passingValue": true,
                    "selections": [
                      {
                        "alias": "allLabels",
                        "args": (v12/*: any*/),
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
                            "selections": (v13/*: any*/),
                            "storageKey": null
                          }
                        ],
                        "storageKey": "labels(first:100)"
                      }
                    ]
                  },
                  (v7/*: any*/)
                ],
                "storageKey": null
              }
            ],
            "type": "Issue",
            "abstractKey": null
          },
          (v7/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "3d912b8c0cd194e312ffb8b34322ba92",
    "metadata": {},
    "name": "useCopilotFetchIssueDataQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "7df76adbbfdaa2d17775704b2c8509c0";

export default node;
