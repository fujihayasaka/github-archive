/**
 * @generated SignedSource<<1ef488ccb0ce577100ce67381ee4fab5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListCurrentViewFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"EditViewButtonCurrentViewFragment" | "HeaderContentCurrentViewFragment" | "HeaderCurrentViewFragment" | "IconAndColorPickerViewFragment" | "SearchBarCurrentViewFragment">;
  readonly " $fragmentType": "ListCurrentViewFragment";
};
export type ListCurrentViewFragment$key = {
  readonly " $data"?: ListCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ListCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ListCurrentViewFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchBarCurrentViewFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderCurrentViewFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "EditViewButtonCurrentViewFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderContentCurrentViewFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IconAndColorPickerViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "c4cdcc580a7e8c3c6d7cafa113c91c8f";

export default node;
