/**
 * @generated SignedSource<<4dd8c6fe54346c0e4255740b35e46bc4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type CreateIssue$data = {
  readonly " $fragmentSpreads": FragmentRefs<"TemplateListPane" | "TemplatePickerButton">;
  readonly " $fragmentType": "CreateIssue";
};
export type CreateIssue$key = {
  readonly " $data"?: CreateIssue$data;
  readonly " $fragmentSpreads": FragmentRefs<"CreateIssue">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": false,
      "kind": "LocalArgument",
      "name": "includeTemplates"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "CreateIssue",
  "selections": [
    {
      "condition": "includeTemplates",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TemplatePickerButton"
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TemplateListPane"
        }
      ]
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "8a3f411e97612f6b11008dffb70a56f0";

export default node;
