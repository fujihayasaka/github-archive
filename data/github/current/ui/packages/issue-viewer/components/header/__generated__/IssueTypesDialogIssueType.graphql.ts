/**
 * @generated SignedSource<<e86f4b01a7d066fd529ed00314ace958>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypesDialogIssueType$data = {
  readonly id: string;
  readonly " $fragmentType": "IssueTypesDialogIssueType";
};
export type IssueTypesDialogIssueType$key = {
  readonly " $data"?: IssueTypesDialogIssueType$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTypesDialogIssueType">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTypesDialogIssueType",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    }
  ],
  "type": "IssueType",
  "abstractKey": null
};

(node as any).hash = "7faaf5aa482aee1bd279904997f497df";

export default node;
