/**
 * @generated SignedSource<<10ebab8b2cc48b2e8ee9247ea7027e9a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerAssigneesBoxItem_Fragment$data = {
  readonly avatarUrl: string;
  readonly login: string;
  readonly " $fragmentType": "ItemPickerAssigneesBoxItem_Fragment";
};
export type ItemPickerAssigneesBoxItem_Fragment$key = {
  readonly " $data"?: ItemPickerAssigneesBoxItem_Fragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerAssigneesBoxItem_Fragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ItemPickerAssigneesBoxItem_Fragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    },
    {
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
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "b9b81a612852a84ed08755156e6d307a";

export default node;
