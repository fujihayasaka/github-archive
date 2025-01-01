/**
 * @generated SignedSource<<bb053a5c40402bc5b0f96f49e12ee990>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type searchInputMilestone$data = {
  readonly closed: boolean;
  readonly id: string;
  readonly title: string;
  readonly " $fragmentType": "searchInputMilestone";
};
export type searchInputMilestone$key = {
  readonly " $data"?: searchInputMilestone$data;
  readonly " $fragmentSpreads": FragmentRefs<"searchInputMilestone">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "searchInputMilestone"
};

(node as any).hash = "25725c8585936addfbf60c431dd10621";

export default node;
