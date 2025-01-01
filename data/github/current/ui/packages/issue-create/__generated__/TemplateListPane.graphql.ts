/**
 * @generated SignedSource<<44db1433e6ad1680ffb752f76c2c854a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplateListPane$data = {
  readonly hasIssuesEnabled: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"TemplateList">;
  readonly " $fragmentType": "TemplateListPane";
};
export type TemplateListPane$key = {
  readonly " $data"?: TemplateListPane$data;
  readonly " $fragmentSpreads": FragmentRefs<"TemplateListPane">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TemplateListPane",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasIssuesEnabled",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TemplateList"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "881cdbdb34820ab9cdf5b5c8e6409bb0";

export default node;
