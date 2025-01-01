/**
 * @generated SignedSource<<0eb379338131087cb1fcdea02f2bd729>>
 * @relayHash c64e6ba36203e1baee1d8517134d7d4c
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID c64e6ba36203e1baee1d8517134d7d4c

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSingleSelectFieldPickerFieldQuery$variables = {
  id: string;
};
export type IssueSingleSelectFieldPickerFieldQuery$data = {
  readonly node: {
    readonly options?: ReadonlyArray<{
      readonly " $fragmentSpreads": FragmentRefs<"IssueSingleSelectFieldPickerOption">;
    }>;
  } | null | undefined;
};
export type IssueSingleSelectFieldPickerFieldQuery = {
  response: IssueSingleSelectFieldPickerFieldQuery$data;
  variables: IssueSingleSelectFieldPickerFieldQuery$variables;
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
  "name": "id",
  "storageKey": null
},
v3 = [
  (v2/*: any*/),
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
    "name": "description",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "color",
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "IssueSingleSelectFieldPickerFieldQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueFieldSingleSelectOption",
                "kind": "LinkedField",
                "name": "options",
                "plural": true,
                "selections": [
                  {
                    "kind": "InlineDataFragmentSpread",
                    "name": "IssueSingleSelectFieldPickerOption",
                    "selections": (v3/*: any*/),
                    "args": null,
                    "argumentDefinitions": []
                  }
                ],
                "storageKey": null
              }
            ],
            "type": "IssueFieldSingleSelect",
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "IssueSingleSelectFieldPickerFieldQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
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
              {
                "alias": null,
                "args": null,
                "concreteType": "IssueFieldSingleSelectOption",
                "kind": "LinkedField",
                "name": "options",
                "plural": true,
                "selections": (v3/*: any*/),
                "storageKey": null
              }
            ],
            "type": "IssueFieldSingleSelect",
            "abstractKey": null
          },
          (v2/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "c64e6ba36203e1baee1d8517134d7d4c",
    "metadata": {},
    "name": "IssueSingleSelectFieldPickerFieldQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "0979e35fc8348ec832d8c8f2a2b59fec";

export default node;
