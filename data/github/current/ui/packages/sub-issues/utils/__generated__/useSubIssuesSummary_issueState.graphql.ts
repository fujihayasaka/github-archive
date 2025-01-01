/**
 * @generated SignedSource<<b7e1029a6cbabbb8d31ba32484e59279>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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
