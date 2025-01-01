/**
 * @generated SignedSource<<2a60b3ef8d8e3642b606166e4e6ad97b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
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
