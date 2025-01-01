/**
 * @generated SignedSource<<0dcb78809501c76f181ec12ae9d0449f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneePickerAssignee$data = {
  readonly __typename: string;
  readonly avatarUrl: string;
  readonly id: string;
  readonly isCopilot?: boolean;
  readonly login: string;
  readonly name: string | null | undefined;
  readonly profileResourcePath: string | null | undefined;
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

(node as any).hash = "51e29765673901bbb4036060ed44d2ea";

export default node;
