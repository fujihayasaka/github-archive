/**
 * @generated SignedSource<<6b0c3c65b133cc5de8b7b13c4ad72631>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ListCurrentViewFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"HeaderCurrentViewFragment" | "SearchCurrentViewFragment">;
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
      "name": "SearchCurrentViewFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderCurrentViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "05ee3fdaa319a2a74e5b5a03a864a22f";

export default node;
