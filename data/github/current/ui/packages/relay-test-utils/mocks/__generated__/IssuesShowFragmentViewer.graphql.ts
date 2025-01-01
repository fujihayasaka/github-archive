/**
 * @generated SignedSource<<45a47053538a67e45b437f0593f6484f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssuesShowFragmentViewer$data = {
  readonly name: string | null | undefined;
  readonly " $fragmentType": "IssuesShowFragmentViewer";
};
export type IssuesShowFragmentViewer$key = {
  readonly " $data"?: IssuesShowFragmentViewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuesShowFragmentViewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuesShowFragmentViewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "1a805346918ee092ed8887e292701e99";

export default node;
