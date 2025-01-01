/**
 * @generated SignedSource<<a0ebebcf760fc412653c2326fa524623>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneIssuesListInternal$data = {
  readonly id: string;
  readonly number: number;
  readonly updatedAt: string;
  readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestoneIssues">;
  readonly " $fragmentType": "MilestoneIssuesListInternal";
};
export type MilestoneIssuesListInternal$key = {
  readonly " $data"?: MilestoneIssuesListInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneIssuesListInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneIssuesListInternal",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "updatedAt",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "OpenClosedMilestoneIssues"
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "4b1062184102941393701896eeda1e42";

export default node;
