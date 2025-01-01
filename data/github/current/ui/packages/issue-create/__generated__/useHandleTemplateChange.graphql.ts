/**
 * @generated SignedSource<<109c498a76139ec4a64b79ac2df79468>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useHandleTemplateChange$data = {
  readonly issueForm: {
    readonly " $fragmentSpreads": FragmentRefs<"useHandleTemplateChangeIssueForm">;
  } | null | undefined;
  readonly issueTemplate: {
    readonly " $fragmentSpreads": FragmentRefs<"useHandleTemplateChangeIssueTemplate">;
  } | null | undefined;
  readonly " $fragmentType": "useHandleTemplateChange";
};
export type useHandleTemplateChange$key = {
  readonly " $data"?: useHandleTemplateChange$data;
  readonly " $fragmentSpreads": FragmentRefs<"useHandleTemplateChange">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "useHandleTemplateChange"
};

(node as any).hash = "a08364bb21fe7bb90b32c5dd4a84a3c6";

export default node;
