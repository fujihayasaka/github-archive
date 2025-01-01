/**
 * @generated SignedSource<<c429dbee9b34c4e881b6b85af975089c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRowTitle$data = {
  readonly title: string;
  readonly url: string;
  readonly " $fragmentType": "MilestoneRowTitle";
};
export type MilestoneRowTitle$key = {
  readonly " $data"?: MilestoneRowTitle$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneRowTitle">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneRowTitle",
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
      "name": "url",
      "storageKey": null
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "5bc05bbe94a56bd64216010d45ac7f03";

export default node;
