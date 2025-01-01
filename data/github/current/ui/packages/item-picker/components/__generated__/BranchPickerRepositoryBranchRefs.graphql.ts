/**
 * @generated SignedSource<<cb0cae8b6f38a477381b4fafce7e8619>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
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
