/**
 * @generated SignedSource<<706bc0c48b032b09eebdbbaf86b7408f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueDashboardCustomViewPageCurrentViewFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"HeaderCurrentViewFragment">;
  readonly " $fragmentType": "IssueDashboardCustomViewPageCurrentViewFragment";
};
export type IssueDashboardCustomViewPageCurrentViewFragment$key = {
  readonly " $data"?: IssueDashboardCustomViewPageCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueDashboardCustomViewPageCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueDashboardCustomViewPageCurrentViewFragment",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderCurrentViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "a93246eb19a6ce78ccda6b3c1177859f";

export default node;
