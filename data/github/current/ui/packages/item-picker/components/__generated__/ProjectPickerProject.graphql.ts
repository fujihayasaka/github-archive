/**
 * @generated SignedSource<<409a1fdfc63e8b65a03b4453bc2c1cd4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ProjectPickerProject$data = {
  readonly __typename: "ProjectV2";
  readonly closed: boolean;
  readonly hasReachedItemsLimit: boolean;
  readonly id: string;
  readonly number: number;
  readonly title: string;
  readonly url: string;
  readonly viewerCanUpdate: boolean;
  readonly " $fragmentType": "ProjectPickerProject";
};
export type ProjectPickerProject$key = {
  readonly " $data"?: ProjectPickerProject$data;
  readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "ProjectPickerProject"
};

(node as any).hash = "682212a921e9bca94528a0423c595cde";

export default node;
