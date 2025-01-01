/**
 * @generated SignedSource<<78c0544fe8209a525d8bbc62b3ee4817>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type AssigneePickerInstallationBot$data = {
  readonly app: {
    readonly logoUrl: string;
    readonly name: string;
    readonly slug: string;
  };
  readonly id: string;
  readonly " $fragmentType": "AssigneePickerInstallationBot";
};
export type AssigneePickerInstallationBot$key = {
  readonly " $data"?: AssigneePickerInstallationBot$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerInstallationBot">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "AssigneePickerInstallationBot"
};

(node as any).hash = "50c467a2088d125c76c3b36e4c9a6fa9";

export default node;
