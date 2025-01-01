/**
 * @generated SignedSource<<34c10168e3decd08fa8d8576813525ee>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type HeaderSubIssueSummaryWithPrimary$data = {
  readonly " $fragmentSpreads": FragmentRefs<"useSubIssuesSummary">;
  readonly " $fragmentType": "HeaderSubIssueSummaryWithPrimary";
};
export type HeaderSubIssueSummaryWithPrimary$key = {
  readonly " $data"?: HeaderSubIssueSummaryWithPrimary$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderSubIssueSummaryWithPrimary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderSubIssueSummaryWithPrimary",
  "selections": [
    {
      "args": [
        {
          "kind": "Literal",
          "name": "fetchSubIssues",
          "value": false
        }
      ],
      "kind": "FragmentSpread",
      "name": "useSubIssuesSummary"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "02a4f342f6c913a3e3f1bba2edd8295d";

export default node;
