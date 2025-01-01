/**
 * @generated SignedSource<<2858ab790df4b34a17efdcb09ee0d9f9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneePickerAssignee$data = {
  readonly avatarUrl: string;
  readonly id: string;
  readonly login: string;
  readonly name: string | null | undefined;
  readonly " $fragmentType": "AssigneePickerAssignee";
};
export type AssigneePickerAssignee$key = {
  readonly " $data"?: AssigneePickerAssignee$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "AssigneePickerAssignee"
};

(node as any).hash = "93765ac9e906ac74c406fb6c6e1aa1be";

export default node;
