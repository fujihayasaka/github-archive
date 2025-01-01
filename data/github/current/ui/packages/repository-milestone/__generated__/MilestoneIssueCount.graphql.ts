/**
 * @generated SignedSource<<ae65e505ecdb866b767eb48f23c0a2c1>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneIssueCount$data = {
  readonly closedIssueCount: number;
  readonly openIssueCount: number;
  readonly " $fragmentType": "MilestoneIssueCount";
};
export type MilestoneIssueCount$key = {
  readonly " $data"?: MilestoneIssueCount$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneIssueCount">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneIssueCount",
  "selections": [
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
      "name": "openIssueCount",
      "storageKey": null
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "15f84a40e0bbfcf780c02f604ec96267";

export default node;
