/**
 * @generated SignedSource<<44e9b8ceae0ccea311115c3f6b575d96>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueFieldPickerPaginated$data = {
  readonly issueFields: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"IssueFieldPickerIssueField">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly " $fragmentType": "IssueFieldPickerPaginated";
};
export type IssueFieldPickerPaginated$key = {
  readonly " $data"?: IssueFieldPickerPaginated$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueFieldPickerPaginated">;
};

const node: ReaderFragment = (function(){
var v0 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "id",
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
    "name": "dataType",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "issueFieldsPageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      {
        "count": "issueFieldsPageSize",
        "cursor": null,
        "direction": "forward",
        "path": [
          "issueFields"
        ]
      }
    ]
  },
  "name": "IssueFieldPickerPaginated",
  "selections": [
    {
      "alias": "issueFields",
      "args": null,
      "concreteType": "IssueFieldsConnection",
      "kind": "LinkedField",
      "name": "__Organization_issueFields_connection",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "IssueFieldsEdge",
          "kind": "LinkedField",
          "name": "edges",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "node",
              "plural": false,
              "selections": [
                {
                  "kind": "InlineDataFragmentSpread",
                  "name": "IssueFieldPickerIssueField",
                  "selections": [
                    {
                      "kind": "InlineFragment",
                      "selections": (v0/*: any*/),
                      "type": "IssueFieldText",
                      "abstractKey": null
                    },
                    {
                      "kind": "InlineFragment",
                      "selections": (v0/*: any*/),
                      "type": "IssueFieldSingleSelect",
                      "abstractKey": null
                    }
                  ],
                  "args": null,
                  "argumentDefinitions": []
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "__typename",
                  "storageKey": null
                }
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
      "storageKey": null
    }
  ],
  "type": "Organization",
  "abstractKey": null
};
})();

(node as any).hash = "8a6dd6e5fd4fe5d70ead8019af2bbe61";

export default node;
