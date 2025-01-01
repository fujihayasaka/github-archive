/**
 * @generated SignedSource<<5ca1133d2ebeced692af882afe9e60fe>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeader_issue$data = {
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions_issue">;
  readonly " $fragmentType": "IssueBodyHeader_issue";
};
export type IssueBodyHeader_issue$key = {
  readonly " $data"?: IssueBodyHeader_issue$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeader_issue">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeader_issue",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyHeaderActions_issue"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "cdc81fa5a3b73da80dba9315187c1521";

export default node;
