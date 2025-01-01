/**
 * @generated SignedSource<<6c47c193604b0c6b0ed853dce613ceea>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerLabelsItem_Fragment$data = {
  readonly color: string;
  readonly description: string | null | undefined;
  readonly id: string;
  readonly name: string;
  readonly nameHTML: string;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerLabelsItem_DateFragment" | "ItemPickerLabelsItem_PathFragment">;
  readonly " $fragmentType": "ItemPickerLabelsItem_Fragment";
};
export type ItemPickerLabelsItem_Fragment$key = {
  readonly " $data"?: ItemPickerLabelsItem_Fragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerLabelsItem_Fragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "ItemPickerLabelsItem_Fragment"
};

(node as any).hash = "22f65b0c817ab10fac31230586e56a03";

export default node;
