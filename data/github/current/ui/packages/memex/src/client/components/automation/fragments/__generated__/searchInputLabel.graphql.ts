/**
 * @generated SignedSource<<a49a3c43dfa54812aeb150906c481a56>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type searchInputLabel$data = {
  readonly color: string;
  readonly description: string | null | undefined;
  readonly id: string;
  readonly name: string;
  readonly nameHTML: string;
  readonly " $fragmentType": "searchInputLabel";
};
export type searchInputLabel$key = {
  readonly " $data"?: searchInputLabel$data;
  readonly " $fragmentSpreads": FragmentRefs<"searchInputLabel">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "searchInputLabel"
};

(node as any).hash = "52a949cfd65641f7e70925d735bf135d";

export default node;
