/**
 * @generated SignedSource<<59f60817ff7f062d2d965ad2c1379ed6>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ItemPickerPullRequestsAndBranchesItem_BranchFragment$data = {
  readonly __typename: "Ref";
  readonly id: string;
  readonly title: string;
  readonly " $fragmentType": "ItemPickerPullRequestsAndBranchesItem_BranchFragment";
};
export type ItemPickerPullRequestsAndBranchesItem_BranchFragment$key = {
  readonly " $data"?: ItemPickerPullRequestsAndBranchesItem_BranchFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ItemPickerPullRequestsAndBranchesItem_BranchFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "ItemPickerPullRequestsAndBranchesItem_BranchFragment"
};

(node as any).hash = "6462b8c82fe7cb5b6b4cd02e72ca598b";

export default node;
