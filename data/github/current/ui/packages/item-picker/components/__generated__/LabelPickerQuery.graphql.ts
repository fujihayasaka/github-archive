/**
 * @generated SignedSource<<617e65b21faaa586b878b24f4d735356>>
 * @relayHash b480cbd1d6d3f7ba4a98229e88acf3fd
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID b480cbd1d6d3f7ba4a98229e88acf3fd

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabelPickerQuery$variables = {
  count?: number | null | undefined;
  labelNames?: string | null | undefined;
  owner: string;
  repo: string;
  shouldQueryByNames?: boolean | null | undefined;
};
export type LabelPickerQuery$data = {
  readonly repository: {
    readonly labelsByNames?: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
      } | null | undefined> | null | undefined;
    } | null | undefined;
    readonly viewerIssueCreationPermissions: {
      readonly labelable: boolean;
    };
    readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabelsPaginated">;
  } | null | undefined;
};
export type LabelPickerQuery = {
  response: LabelPickerQuery$data;
  variables: LabelPickerQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": 100,
  "kind": "LocalArgument",
  "name": "count"
},
v1 = {
  "defaultValue": "",
  "kind": "LocalArgument",
  "name": "labelNames"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v3 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v4 = {
  "defaultValue": false,
  "kind": "LocalArgument",
  "name": "shouldQueryByNames"
},
v5 = [
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
v6 = {
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
    }
  ],
  "storageKey": null
},
v7 = {
  "kind": "Literal",
  "name": "orderBy",
  "value": {
    "direction": "ASC",
    "field": "NAME"
  }
},
v8 = [
  {
    "kind": "Variable",
    "name": "first",
    "variableName": "count"
  },
  {
    "kind": "Variable",
    "name": "names",
    "variableName": "labelNames"
  },
  (v7/*: any*/)
],
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v10 = [
  (v9/*: any*/),
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
    "name": "name",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameHTML",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "description",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "url",
    "storageKey": null
  }
],
v11 = {
  "alias": null,
  "args": null,
  "concreteType": "Label",
  "kind": "LinkedField",
  "name": "nodes",
  "plural": true,
  "selections": (v10/*: any*/),
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/),
      (v3/*: any*/),
      (v4/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "LabelPickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v6/*: any*/),
          {
            "args": null,
            "kind": "FragmentSpread",
            "name": "LabelPickerLabelsPaginated"
          },
          {
            "condition": "shouldQueryByNames",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": "labelsByNames",
                "args": (v8/*: any*/),
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
                        "selections": (v10/*: any*/),
                        "args": null,
                        "argumentDefinitions": []
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": null
              }
            ]
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
      (v3/*: any*/),
      (v4/*: any*/),
      (v1/*: any*/),
      (v0/*: any*/)
    ],
    "kind": "Operation",
    "name": "LabelPickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v5/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          (v6/*: any*/),
          (v9/*: any*/),
          {
            "alias": null,
            "args": [
              {
                "kind": "Literal",
                "name": "first",
                "value": 100
              },
              (v7/*: any*/)
            ],
            "concreteType": "LabelConnection",
            "kind": "LinkedField",
            "name": "labels",
            "plural": false,
            "selections": [
              (v11/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "totalCount",
                "storageKey": null
              }
            ],
            "storageKey": "labels(first:100,orderBy:{\"direction\":\"ASC\",\"field\":\"NAME\"})"
          },
          {
            "condition": "shouldQueryByNames",
            "kind": "Condition",
            "passingValue": true,
            "selections": [
              {
                "alias": "labelsByNames",
                "args": (v8/*: any*/),
                "concreteType": "LabelConnection",
                "kind": "LinkedField",
                "name": "labels",
                "plural": false,
                "selections": [
                  (v11/*: any*/)
                ],
                "storageKey": null
              }
            ]
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "b480cbd1d6d3f7ba4a98229e88acf3fd",
    "metadata": {},
    "name": "LabelPickerQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "f2a0198cb8fd64daf4870ea252f764be";

export default node;
