/**
 * @generated SignedSource<<b95cd78e7e4ac2b292abf0c23715f58a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useHandleTemplateChangeIssueTemplate$data = {
  readonly __typename: "IssueTemplate";
  readonly __id: string;
  readonly assignees: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  };
  readonly body: string | null | undefined;
  readonly filename: string;
  readonly labels: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly name: string;
  readonly title: string | null | undefined;
  readonly type: {
    readonly " $fragmentSpreads": FragmentRefs<"IssueTypePickerIssueType">;
  } | null | undefined;
  readonly " $fragmentType": "useHandleTemplateChangeIssueTemplate";
};
export type useHandleTemplateChangeIssueTemplate$key = {
  readonly " $data"?: useHandleTemplateChangeIssueTemplate$data;
  readonly " $fragmentSpreads": FragmentRefs<"useHandleTemplateChangeIssueTemplate">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "useHandleTemplateChangeIssueTemplate"
};

(node as any).hash = "190435c14d7c2d5662106aaaf1dcd412";

export default node;
