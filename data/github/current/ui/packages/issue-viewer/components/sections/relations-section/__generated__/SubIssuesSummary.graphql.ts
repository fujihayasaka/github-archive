/**
 * @generated SignedSource<<4671c1d7b3c972dda192fbb74f9caa1f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssuesSummary$data = {
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"useSubIssuesSummary">;
  readonly " $fragmentType": "SubIssuesSummary";
};
export type SubIssuesSummary$key = {
  readonly " $data"?: SubIssuesSummary$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssuesSummary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssuesSummary",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
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

(node as any).hash = "5a7187edce3938a43fece98cebbed5eb";

export default node;
