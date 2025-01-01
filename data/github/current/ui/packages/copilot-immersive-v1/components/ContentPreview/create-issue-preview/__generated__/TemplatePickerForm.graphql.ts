/**
 * @generated SignedSource<<285e50b0277c50fce629b57a22348f46>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplatePickerForm$data = {
  readonly __typename: "IssueForm";
  readonly description: string | null | undefined;
  readonly filename: string;
  readonly name: string;
  readonly " $fragmentType": "TemplatePickerForm";
};
export type TemplatePickerForm$key = {
  readonly " $data"?: TemplatePickerForm$data;
  readonly " $fragmentSpreads": FragmentRefs<"TemplatePickerForm">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "TemplatePickerForm"
};

(node as any).hash = "277026edd019ed6ef2c9d27b3d3d6c4a";

export default node;
