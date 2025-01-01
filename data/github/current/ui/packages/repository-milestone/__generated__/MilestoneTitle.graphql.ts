/**
 * @generated SignedSource<<49e8bcd4b8f1f015ea317a96dcc892fc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneTitle$data = {
  readonly repository: {
    readonly nameWithOwner: string;
  };
  readonly title: string;
  readonly " $fragmentType": "MilestoneTitle";
};
export type MilestoneTitle$key = {
  readonly " $data"?: MilestoneTitle$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneTitle">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneTitle",
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
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameWithOwner",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "3aa545b4589bf0d967e46deb8f691360";

export default node;
