/**
 * @generated SignedSource<<1ae57fe38c2d73de8501d999db217760>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderSecondary$data = {
  readonly isTransferInProgress: boolean;
  readonly " $fragmentType": "HeaderSecondary";
};
export type HeaderSecondary$key = {
  readonly " $data"?: HeaderSecondary$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderSecondary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderSecondary",
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

(node as any).hash = "58a7f4c970dd56751203ee21d03734e9";

export default node;
