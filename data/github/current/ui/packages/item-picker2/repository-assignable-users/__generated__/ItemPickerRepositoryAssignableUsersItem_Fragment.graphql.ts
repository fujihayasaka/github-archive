/**
 * @generated SignedSource<<95a946c90d22bc265d4065be3d7605c0>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerRepositoryAssignableUsersItem_Fragment$data = {
  readonly avatarUrl: string;
  readonly id: string;
  readonly login: string;
  readonly name: string | null | undefined;
  readonly " $fragmentType": "ItemPickerRepositoryAssignableUsersItem_Fragment";
};
export type ItemPickerRepositoryAssignableUsersItem_Fragment$key = {
  readonly " $data"?: ItemPickerRepositoryAssignableUsersItem_Fragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerRepositoryAssignableUsersItem_Fragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "ItemPickerRepositoryAssignableUsersItem_Fragment"
};

(node as any).hash = "190d4c58da1a76a442d5bd2894ee7ecd";

export default node;
