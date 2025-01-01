/**
 * @generated SignedSource<<3003ed1fd7b245331c1504abbbf4ecc5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueFormElements_templateElements$data = {
  readonly elements: ReadonlyArray<{
    readonly __typename: "IssueFormElementCheckboxes";
    readonly " $fragmentSpreads": FragmentRefs<"CheckboxesElement_input">;
  } | {
    readonly __typename: "IssueFormElementDropdown";
    readonly " $fragmentSpreads": FragmentRefs<"DropdownElement_input">;
  } | {
    readonly __typename: "IssueFormElementInput";
    readonly " $fragmentSpreads": FragmentRefs<"TextInputElement_input">;
  } | {
    readonly __typename: "IssueFormElementMarkdown";
    readonly " $fragmentSpreads": FragmentRefs<"MarkdownElement_input">;
  } | {
    readonly __typename: "IssueFormElementTextarea";
    readonly " $fragmentSpreads": FragmentRefs<"TextAreaElement_input">;
  } | {
    // This will never be '%other', but we need some
    // value in case none of the concrete values match.
    readonly __typename: "%other";
  }>;
  readonly " $fragmentType": "IssueFormElements_templateElements";
};
export type IssueFormElements_templateElements$key = {
  readonly " $data"?: IssueFormElements_templateElements$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueFormElements_templateElements">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "IssueFormElements_templateElements"
};

(node as any).hash = "8c027995abd00c22fac1d025a14e2a8d";

export default node;
