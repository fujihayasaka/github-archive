/**
 * @generated SignedSource<<3a751193d17abe1d96ef3b114bb31d87>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
export type IssueFieldDataType = "SINGLE_SELECT" | "TEXT" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssueFieldPickerIssueField$data = {
  readonly dataType?: IssueFieldDataType;
  readonly id?: string;
  readonly name?: string;
  readonly " $fragmentType": "IssueFieldPickerIssueField";
};
export type IssueFieldPickerIssueField$key = {
  readonly " $data"?: IssueFieldPickerIssueField$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueFieldPickerIssueField">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "IssueFieldPickerIssueField"
};

(node as any).hash = "7ea9a588ce57b5d2c9bd83588e43bdbb";

export default node;
