/**
 * @generated SignedSource<<1717b9b90476559247fce223cac8b0d6>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerProjectsBoxItem_ClassicFragment$data = {
  readonly title: string;
  readonly url: string;
  readonly " $fragmentType": "ItemPickerProjectsBoxItem_ClassicFragment";
};
export type ItemPickerProjectsBoxItem_ClassicFragment$key = {
  readonly " $data"?: ItemPickerProjectsBoxItem_ClassicFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerProjectsBoxItem_ClassicFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ItemPickerProjectsBoxItem_ClassicFragment",
  "selections": [
    {
      "alias": "title",
      "args": null,
      "kind": "ScalarField",
      "name": "name",
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
  "type": "Project",
  "abstractKey": null
};

(node as any).hash = "5c4ec730d028216593de50a7cb355cf8";

export default node;
