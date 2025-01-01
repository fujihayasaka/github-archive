/**
 * @generated SignedSource<<7d672f8bcf2d3c3ed1db7de006246a0b>>
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

(node as any).hash = "6bac26855f609043b950b952fed1e254";

export default node;
