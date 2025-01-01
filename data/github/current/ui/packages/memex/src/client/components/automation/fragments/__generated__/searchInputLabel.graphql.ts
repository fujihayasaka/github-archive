/**
 * @generated SignedSource<<7e8ff9993e0b6bd648eaca915cd5b611>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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
