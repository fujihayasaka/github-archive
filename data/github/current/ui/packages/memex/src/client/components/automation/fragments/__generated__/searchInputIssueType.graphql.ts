/**
 * @generated SignedSource<<da9a844cb9bc82a18d43936b9110bdae>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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
