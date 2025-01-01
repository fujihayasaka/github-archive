/**
 * @generated SignedSource<<6c05f03b4a0c9f2d8e3e491690651980>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneRowMetadata$data = {
  readonly closedIssueCount: number;
  readonly openIssueCount: number;
  readonly progressPercentage: number;
  readonly title: string;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneRowMenu">;
  readonly " $fragmentType": "MilestoneRowMetadata";
};
export type MilestoneRowMetadata$key = {
  readonly " $data"?: MilestoneRowMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneRowMetadata">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneRowMetadata",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneRowMenu"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "progressPercentage",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "openIssueCount",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "closedIssueCount",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "title",
      "storageKey": null
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "db345f0e64434fb83335b93532e33afd";

export default node;
