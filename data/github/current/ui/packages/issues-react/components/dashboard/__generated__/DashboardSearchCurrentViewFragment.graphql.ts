/**
 * @generated SignedSource<<9561a58d5740fd8eaf558b4f874ffac9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DashboardSearchCurrentViewFragment$data = {
  readonly query: string;
  readonly " $fragmentSpreads": FragmentRefs<"DashboardEditViewActionsFragment" | "DashboardSearchBarActionsFragment" | "SearchBarCurrentViewFragment">;
  readonly " $fragmentType": "DashboardSearchCurrentViewFragment";
};
export type DashboardSearchCurrentViewFragment$key = {
  readonly " $data"?: DashboardSearchCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"DashboardSearchCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DashboardSearchCurrentViewFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "query",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DashboardSearchBarActionsFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DashboardEditViewActionsFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SearchBarCurrentViewFragment"
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "a8438ebbf35da2ba8c7c5360a65efc1f";

export default node;
