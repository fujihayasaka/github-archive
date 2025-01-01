/**
 * @generated SignedSource<<8744a1fefb8b1f7b4e99ba937caa898a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplatePickerButton$data = {
  readonly hasAnyTemplates: boolean;
  readonly nameWithOwner: string;
  readonly " $fragmentType": "TemplatePickerButton";
};
export type TemplatePickerButton$key = {
  readonly " $data"?: TemplatePickerButton$data;
  readonly " $fragmentSpreads": FragmentRefs<"TemplatePickerButton">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TemplatePickerButton",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasAnyTemplates",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "fc9ace64aa764ca00db0ea2f61b67a2b";

export default node;
