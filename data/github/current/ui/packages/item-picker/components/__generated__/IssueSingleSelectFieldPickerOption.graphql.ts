/**
 * @generated SignedSource<<0bed6e84c74b795eb327f77db18a644a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
export type IssueFieldSingleSelectOptionColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssueSingleSelectFieldPickerOption$data = {
  readonly color: IssueFieldSingleSelectOptionColor;
  readonly description: string | null | undefined;
  readonly id: string;
  readonly name: string;
  readonly " $fragmentType": "IssueSingleSelectFieldPickerOption";
};
export type IssueSingleSelectFieldPickerOption$key = {
  readonly " $data"?: IssueSingleSelectFieldPickerOption$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueSingleSelectFieldPickerOption">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "IssueSingleSelectFieldPickerOption"
};

(node as any).hash = "d8bcb73a6758269a0f127f7a03e396bc";

export default node;
