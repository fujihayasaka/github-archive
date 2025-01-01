/**
 * @generated SignedSource<<729225bda4e5c0006b28b8628c910e1f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderContentCurrentViewFragment$data = {
  readonly description: string;
  readonly id: string;
  readonly name: string;
  readonly " $fragmentSpreads": FragmentRefs<"IconAndColorPickerViewFragment" | "ViewOptionsButtonCurrentViewFragment">;
  readonly " $fragmentType": "HeaderContentCurrentViewFragment";
};
export type HeaderContentCurrentViewFragment$key = {
  readonly " $data"?: HeaderContentCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderContentCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderContentCurrentViewFragment",
  "selections": [
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
      "name": "id",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IconAndColorPickerViewFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "ViewOptionsButtonCurrentViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "f305cee1d125371a31f8f260f6725199";

export default node;
