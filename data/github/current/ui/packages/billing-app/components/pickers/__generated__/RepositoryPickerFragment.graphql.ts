/**
 * @generated SignedSource<<32170ace30aca00e54e222e262203e7d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryPickerFragment$data = {
  readonly id: string;
  readonly isArchived: boolean;
  readonly isPrivate: boolean;
  readonly nameWithOwner: string;
  readonly " $fragmentType": "RepositoryPickerFragment";
};
export type RepositoryPickerFragment$key = {
  readonly " $data"?: RepositoryPickerFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryPickerFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "RepositoryPickerFragment"
};

(node as any).hash = "cc97e0ef055002f971ffd9c154fe65f4";

export default node;
