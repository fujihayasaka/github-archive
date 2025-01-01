/**
 * @generated SignedSource<<db21336e75ee5acad4cef9ea24c5ba0e>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueMetadata$data = {
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionAssignees" | "LabelsSectionAssignedLabels" | "MilestonesSectionMilestone">;
  readonly " $fragmentType": "IssueMetadata";
};
export type IssueMetadata$key = {
  readonly " $data"?: IssueMetadata$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueMetadata">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueMetadata",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LabelsSectionAssignedLabels"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "AssigneesSectionAssignees"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestonesSectionMilestone"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "d58846f98442c160672513c6ce32b5a2";

export default node;
