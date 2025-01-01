/**
 * @generated SignedSource<<80e37bb22811928c79c0a9824c0b057c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OpenClosedMilestoneIssues$data = {
  readonly closedIssueCount: number;
  readonly openIssueCount: number;
  readonly " $fragmentType": "OpenClosedMilestoneIssues";
};
export type OpenClosedMilestoneIssues$key = {
  readonly " $data"?: OpenClosedMilestoneIssues$data;
  readonly " $fragmentSpreads": FragmentRefs<"OpenClosedMilestoneIssues">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "OpenClosedMilestoneIssues",
  "selections": [
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
    }
  ],
  "type": "Milestone",
  "abstractKey": null
};

(node as any).hash = "91b6ba0a2d4f55865eaf8fbec036f6bd";

export default node;
