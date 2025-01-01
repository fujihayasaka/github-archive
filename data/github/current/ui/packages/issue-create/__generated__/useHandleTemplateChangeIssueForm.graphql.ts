/**
 * @generated SignedSource<<7ff3d6dbb516fdbaf83c6b0812261771>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useHandleTemplateChangeIssueForm$data = {
  readonly __typename: "IssueForm";
  readonly __id: string;
  readonly assignees: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly filename: string;
  readonly labels: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly name: string;
  readonly projects: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly title: string | null | undefined;
  readonly type: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerIssueType">;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"IssueFormElements_templateElements">;
  readonly " $fragmentType": "useHandleTemplateChangeIssueForm";
};
export type useHandleTemplateChangeIssueForm$key = {
  readonly " $data"?: useHandleTemplateChangeIssueForm$data;
  readonly " $fragmentSpreads": FragmentRefs<"useHandleTemplateChangeIssueForm">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "useHandleTemplateChangeIssueForm"
};

(node as any).hash = "9c61a2da7c131125a2c9b5d1312d84ab";

export default node;
