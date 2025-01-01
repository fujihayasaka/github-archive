/**
 * @generated SignedSource<<558341bed9cb0eef40a3e576e816bedc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabelPickerLabel$data = {
  readonly color: string;
  readonly description: string | null | undefined;
  readonly id: string;
  readonly name: string;
  readonly nameHTML: string;
  readonly url: string;
  readonly " $fragmentType": "LabelPickerLabel";
};
export type LabelPickerLabel$key = {
  readonly " $data"?: LabelPickerLabel$data;
  readonly " $fragmentSpreads": FragmentRefs<"LabelPickerLabel">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "LabelPickerLabel"
};

(node as any).hash = "588236f5485d473e68f4a74b65c0b653";

export default node;
