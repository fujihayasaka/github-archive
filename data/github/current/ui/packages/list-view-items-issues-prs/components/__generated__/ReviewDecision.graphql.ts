/**
 * @generated SignedSource<<6df791d594d093a6d48dc3f2be148a59>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type PullRequestReviewDecision = "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type ReviewDecision$data = {
  readonly reviewDecision: PullRequestReviewDecision | null | undefined;
  readonly " $fragmentType": "ReviewDecision";
};
export type ReviewDecision$key = {
  readonly " $data"?: ReviewDecision$data;
  readonly " $fragmentSpreads": FragmentRefs<"ReviewDecision">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ReviewDecision",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "reviewDecision",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "1c213dcaa975bc9ffa4c8aaaba1c8aec";

export default node;
