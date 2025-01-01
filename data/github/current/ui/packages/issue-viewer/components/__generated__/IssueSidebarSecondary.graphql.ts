/**
 * @generated SignedSource<<e20c37e6eaa661ac5435c236b9fadc7f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueSidebarSecondary$data = {
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionLazyFragment" | "OptionsSectionSecondary">;
  readonly " $fragmentType": "IssueSidebarSecondary";
};
export type IssueSidebarSecondary$key = {
  readonly " $data"?: IssueSidebarSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueSidebarSecondary",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "OptionsSectionSecondary"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "AssigneesSectionLazyFragment"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "8fc24bb52effd976666af3d674ce0d7d";

export default node;
