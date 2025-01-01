/**
 * @generated SignedSource<<fcb217e245ce54ad55ed20fbc29c3c5c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueTypesListList$data = {
  readonly edges: ReadonlyArray<{
    readonly node: {
      readonly id: string;
      readonly name: string;
      readonly " $fragmentSpreads": FragmentRefs<"IssueTypesListItem">;
    } | null | undefined;
  } | null | undefined> | null | undefined;
  readonly totalCount: number;
  readonly " $fragmentType": "IssueTypesListList";
};
export type IssueTypesListList$key = {
  readonly " $data"?: IssueTypesListList$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTypesListList">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTypesListList",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "totalCount",
      "storageKey": null
    },
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
          "selections": [
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
              "args": null,
              "kind": "FragmentSpread",
              "name": "IssueTypesListItem"
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "IssueTypeConnection",
  "abstractKey": null
};

(node as any).hash = "ff07120bdb8568fdc4b115fdfb9f78be";

export default node;
