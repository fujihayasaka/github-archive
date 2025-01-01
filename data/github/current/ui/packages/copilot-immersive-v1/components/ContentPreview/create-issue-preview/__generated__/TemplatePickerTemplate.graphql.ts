/**
 * @generated SignedSource<<f8a627b894b6ddc62135c8cd46e8ba20>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplatePickerTemplate$data = {
  readonly __typename: "IssueTemplate";
  readonly about: string | null | undefined;
  readonly filename: string;
  readonly name: string;
  readonly " $fragmentType": "TemplatePickerTemplate";
};
export type TemplatePickerTemplate$key = {
  readonly " $data"?: TemplatePickerTemplate$data;
  readonly " $fragmentSpreads": FragmentRefs<"TemplatePickerTemplate">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "TemplatePickerTemplate"
};

(node as any).hash = "fa6038bb9389af7bff23ba3491dd0507";

export default node;
