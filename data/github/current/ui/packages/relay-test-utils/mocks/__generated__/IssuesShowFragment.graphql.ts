/**
 * @generated SignedSource<<3fc2d79163d7821bd22c8a24003b2787>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssuesShowFragment$data = {
  readonly number: number;
  readonly title: string;
  readonly " $fragmentType": "IssuesShowFragment";
};
export type IssuesShowFragment$key = {
  readonly " $data"?: IssuesShowFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuesShowFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuesShowFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "title",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "49197d74e9d1f0906438af2e79557dd9";

export default node;
