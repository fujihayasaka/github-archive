/**
 * @generated SignedSource<<0a85cc5ac74805caacba0b4edb70ef00>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueTypeColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssueTypesListItem$data = {
  readonly color: IssueTypeColor;
  readonly description: string | null | undefined;
  readonly id: string;
  readonly isEnabled: boolean;
  readonly name: string;
  readonly " $fragmentSpreads": FragmentRefs<"DeletionConfirmationDialogIssueType" | "DisableOrganizationConfirmationDialogIssueType" | "IssueTypeItemMenuItem">;
  readonly " $fragmentType": "IssueTypesListItem";
};
export type IssueTypesListItem$key = {
  readonly " $data"?: IssueTypesListItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTypesListItem">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTypesListItem",
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
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isEnabled",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "description",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "color",
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
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueTypeItemMenuItem"
    }
  ],
  "type": "IssueType",
  "abstractKey": null
};

(node as any).hash = "f577554a0102148d5547db300a58107a";

export default node;
