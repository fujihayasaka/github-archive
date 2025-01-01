/**
 * @generated SignedSource<<0e6953072134a21990adc5307cd647b5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type DeletionConfirmationDialogIssueType$data = {
  readonly id: string;
  readonly name: string;
  readonly " $fragmentType": "DeletionConfirmationDialogIssueType";
};
export type DeletionConfirmationDialogIssueType$key = {
  readonly " $data"?: DeletionConfirmationDialogIssueType$data;
  readonly " $fragmentSpreads": FragmentRefs<"DeletionConfirmationDialogIssueType">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DeletionConfirmationDialogIssueType",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "IssueType",
  "abstractKey": null
};

(node as any).hash = "8595f18eccc3384ad8eb0872a1977801";

export default node;
