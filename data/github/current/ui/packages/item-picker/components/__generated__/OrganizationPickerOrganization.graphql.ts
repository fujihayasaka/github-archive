/**
 * @generated SignedSource<<1feea03eccfbccd643e95a18adbe953b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OrganizationPickerOrganization$data = {
  readonly avatarUrl: string;
  readonly id: string;
  readonly name: string | null | undefined;
  readonly " $fragmentType": "OrganizationPickerOrganization";
};
export type OrganizationPickerOrganization$key = {
  readonly " $data"?: OrganizationPickerOrganization$data;
  readonly " $fragmentSpreads": FragmentRefs<"OrganizationPickerOrganization">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "OrganizationPickerOrganization"
};

(node as any).hash = "5ed0001897e59aec987a76cce2a9383e";

export default node;
