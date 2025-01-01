/**
 * @generated SignedSource<<0e204d228988d4751a79a92894e38d23>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchCurrentViewFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarCurrentViewFragment">;
  readonly " $fragmentType": "SearchCurrentViewFragment";
};
export type SearchCurrentViewFragment$key = {
  readonly " $data"?: SearchCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SearchCurrentViewFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchBarCurrentViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "866bc486e7c985c0348b2a2761417fad";

export default node;
