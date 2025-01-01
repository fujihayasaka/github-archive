/**
 * @generated SignedSource<<7e3fa02d4bf8186ea650a50574d9ba30>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypePickerPaginated$data = {
  readonly issueTypes: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerIssueType">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
    readonly totalCount: number;
  } | null | undefined;
  readonly " $fragmentType": "IssueTypePickerPaginated";
};
export type IssueTypePickerPaginated$key = {
  readonly " $data"?: IssueTypePickerPaginated$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerPaginated">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "IssueTypePickerPaginated"
};

(node as any).hash = "df15437c426d213fd902540377a337ed";

export default node;
