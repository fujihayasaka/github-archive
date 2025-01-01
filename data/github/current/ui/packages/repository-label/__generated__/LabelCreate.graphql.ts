/**
 * @generated SignedSource<<5fe15676de72e3eb317a82348c63f253>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabelCreate$data = {
  readonly id: string;
  readonly viewerCanPush: boolean;
  readonly " $fragmentType": "LabelCreate";
};
export type LabelCreate$key = {
  readonly " $data"?: LabelCreate$data;
  readonly " $fragmentSpreads": FragmentRefs<"LabelCreate">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "LabelCreate",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "8fb54c2ec326eaca63b8336f3a43368d";

export default node;
