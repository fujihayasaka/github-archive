/**
 * @generated SignedSource<<405623658125a23e6ae13c9e6fdb54ad>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderSubIssueSummary$data = {
  readonly " $fragmentSpreads": FragmentRefs<"useSubIssuesSummary">;
  readonly " $fragmentType": "HeaderSubIssueSummary";
};
export type HeaderSubIssueSummary$key = {
  readonly " $data"?: HeaderSubIssueSummary$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderSubIssueSummary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "fetchSubIssues"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderSubIssueSummary",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "fetchSubIssues",
          "variableName": "fetchSubIssues"
        }
      ],
      "kind": "FragmentSpread",
      "name": "useSubIssuesSummary"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "603b042fa945a22ebcdb8345f0a3a612";

export default node;
