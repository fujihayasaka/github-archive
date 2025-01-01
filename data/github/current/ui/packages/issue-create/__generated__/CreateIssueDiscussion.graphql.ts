/**
 * @generated SignedSource<<05eeb1f36d592461cba9e59e1e904e8e>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type CreateIssueDiscussion$data = {
  readonly formattedBody: string | null | undefined;
  readonly labels: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly title: string;
  readonly " $fragmentType": "CreateIssueDiscussion";
};
export type CreateIssueDiscussion$key = {
  readonly " $data"?: CreateIssueDiscussion$data;
  readonly " $fragmentSpreads": FragmentRefs<"CreateIssueDiscussion">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "CreateIssueDiscussion"
};

(node as any).hash = "3dfe7728cf1710c087c3df24377c8591";

export default node;
