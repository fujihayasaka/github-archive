/**
 * @generated SignedSource<<0c8c411b1133995073a7bd5f4cc4ffc4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type DangerZoneIssueType$data = {
  readonly id: string;
  readonly isEnabled: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"DeletionConfirmationDialogIssueType" | "DisableOrganizationConfirmationDialogIssueType">;
  readonly " $fragmentType": "DangerZoneIssueType";
};
export type DangerZoneIssueType$key = {
  readonly " $data"?: DangerZoneIssueType$data;
  readonly " $fragmentSpreads": FragmentRefs<"DangerZoneIssueType">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DangerZoneIssueType",
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
      "name": "isEnabled",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DisableOrganizationConfirmationDialogIssueType"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DeletionConfirmationDialogIssueType"
    }
  ],
  "type": "IssueType",
  "abstractKey": null
};

(node as any).hash = "b99f63ebae3211501501f852325c8608";

export default node;
