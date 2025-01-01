/**
 * @generated SignedSource<<0f9e7ea50c08d5e3dce9e0708a6dcb7f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type HeaderSubIssueSummary$data = {
  readonly " $fragmentSpreads": FragmentRefs<"useSubIssuesSummary">;
  readonly " $fragmentType": "HeaderSubIssueSummary";
};
export type HeaderSubIssueSummary$key = {
  readonly " $data"?: HeaderSubIssueSummary$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderSubIssueSummary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderSubIssueSummary",
  "selections": [
    {
      "args": [
        {
          "kind": "Literal",
          "name": "fetchSubIssues",
          "value": true
        }
      ],
      "kind": "FragmentSpread",
      "name": "useSubIssuesSummary"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "b9b7b99a1b6a2105fe98f1aff59803e4";

export default node;
