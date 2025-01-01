/**
 * @generated SignedSource<<3f83f98f450a0950e13d44dfc901185a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SubIssuesListViewViewer$data = {
  readonly isEmployee: boolean;
  readonly " $fragmentType": "SubIssuesListViewViewer";
};
export type SubIssuesListViewViewer$key = {
  readonly " $data"?: SubIssuesListViewViewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListViewViewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssuesListViewViewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isEmployee",
      "storageKey": null
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "1aa936852ac406154dfb9323174dd7e7";

export default node;
