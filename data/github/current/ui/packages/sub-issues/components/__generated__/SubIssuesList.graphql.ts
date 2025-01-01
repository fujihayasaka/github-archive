/**
 * @generated SignedSource<<e9e053050f73169ad15ab5925172b08a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SubIssuesList$data = {
  readonly " $fragmentSpreads": FragmentRefs<"AddSubIssueButtonGroup" | "SubIssuesListView">;
  readonly " $fragmentType": "SubIssuesList";
};
export type SubIssuesList$key = {
  readonly " $data"?: SubIssuesList$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssuesList">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssuesList",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "SubIssuesListView"
    },
    {
      "args": [
        {
          "kind": "Literal",
          "name": "fetchSubIssues",
          "value": true
        }
      ],
      "kind": "FragmentSpread",
      "name": "AddSubIssueButtonGroup"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "5392781363d352b5a0f552def559897f";

export default node;
