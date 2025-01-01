/**
 * @generated SignedSource<<8b92a4a3c6beed995c6196af28ebcf8a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type searchInputIssueType$data = {
  readonly id: string;
  readonly isEnabled: boolean;
  readonly name: string;
  readonly " $fragmentType": "searchInputIssueType";
};
export type searchInputIssueType$key = {
  readonly " $data"?: searchInputIssueType$data;
  readonly " $fragmentSpreads": FragmentRefs<"searchInputIssueType">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "searchInputIssueType"
};

(node as any).hash = "0e2c4c3c51227e87bbabb7dad24e212c";

export default node;
