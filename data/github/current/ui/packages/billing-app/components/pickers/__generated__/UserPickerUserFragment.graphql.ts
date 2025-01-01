/**
 * @generated SignedSource<<5c3808b09dad45700c9bf9b92a4561af>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type UserPickerUserFragment$data = {
  readonly avatarUrl: string;
  readonly id: string;
  readonly login: string;
  readonly name: string | null | undefined;
  readonly " $fragmentType": "UserPickerUserFragment";
};
export type UserPickerUserFragment$key = {
  readonly " $data"?: UserPickerUserFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"UserPickerUserFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "UserPickerUserFragment"
};

(node as any).hash = "9a68663559e516b597f9d6fff1332fdf";

export default node;
