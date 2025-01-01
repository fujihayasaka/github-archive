/**
 * @generated SignedSource<<0484b853a79d59f0bab6cb566b46cfa9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useSubIssuesSummary_issueState$data = {
  readonly closed: boolean;
  readonly " $fragmentType": "useSubIssuesSummary_issueState";
};
export type useSubIssuesSummary_issueState$key = {
  readonly " $data"?: useSubIssuesSummary_issueState$data;
  readonly " $fragmentSpreads": FragmentRefs<"useSubIssuesSummary_issueState">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "useSubIssuesSummary_issueState",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "closed",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "515e31dab563432fdb7cf114f8ecc2d8";

export default node;
