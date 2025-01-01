/**
 * @generated SignedSource<<bdce8882a6ae7ac33479c3fa62a2a1f5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type BranchPickerRepositoryBranchRefs$data = {
  readonly defaultBranchRef: {
    readonly " $fragmentSpreads": FragmentRefs<"BranchPickerRef">;
  } | null | undefined;
  readonly id: string;
  readonly refs: {
    readonly " $fragmentSpreads": FragmentRefs<"BranchPickerRepositoryBranches">;
  } | null | undefined;
  readonly " $fragmentType": "BranchPickerRepositoryBranchRefs";
};
export type BranchPickerRepositoryBranchRefs$key = {
  readonly " $data"?: BranchPickerRepositoryBranchRefs$data;
  readonly " $fragmentSpreads": FragmentRefs<"BranchPickerRepositoryBranchRefs">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "BranchPickerRepositoryBranchRefs"
};

(node as any).hash = "3987830ca22f372a937fcef8c7dd5e8b";

export default node;
