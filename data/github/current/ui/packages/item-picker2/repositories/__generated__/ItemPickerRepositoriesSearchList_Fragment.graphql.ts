/**
 * @generated SignedSource<<93d098ddc68bdeb7b873dd33e5112bc5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerRepositoriesSearchList_Fragment$data = {
  readonly nodes: ReadonlyArray<{
    readonly id?: string;
    readonly " $fragmentSpreads": FragmentRefs<"ItemPickerRepositoryItem_Fragment">;
  } | null | undefined> | null | undefined;
  readonly " $fragmentType": "ItemPickerRepositoriesSearchList_Fragment";
};
export type ItemPickerRepositoriesSearchList_Fragment$key = {
  readonly " $data"?: ItemPickerRepositoriesSearchList_Fragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerRepositoriesSearchList_Fragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ItemPickerRepositoriesSearchList_Fragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "nodes",
      "plural": true,
      "selections": [
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "id",
              "storageKey": null
            },
            {
              "args": null,
              "kind": "FragmentSpread",
              "name": "ItemPickerRepositoryItem_Fragment"
            }
          ],
          "type": "Repository",
          "abstractKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "SearchResultItemConnection",
  "abstractKey": null
};

(node as any).hash = "5432585aa80dcb06d08f858d8936fd6a";

export default node;
