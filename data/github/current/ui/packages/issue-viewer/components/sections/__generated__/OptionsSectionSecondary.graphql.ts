/**
 * @generated SignedSource<<69a6100d9afe68adf723dc1e1186e1e5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type OptionsSectionSecondary$data = {
  readonly isTransferInProgress: boolean;
  readonly " $fragmentType": "OptionsSectionSecondary";
};
export type OptionsSectionSecondary$key = {
  readonly " $data"?: OptionsSectionSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"OptionsSectionSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "OptionsSectionSecondary",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isTransferInProgress",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "37235901f5bd1b8bca0d6f9f465df52e";

export default node;
