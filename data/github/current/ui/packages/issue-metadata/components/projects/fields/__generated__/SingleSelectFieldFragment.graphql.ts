/**
 * @generated SignedSource<<99f31214a202905ec1723392eea9a1af>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type ProjectV2SingleSelectFieldOptionColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type SingleSelectFieldFragment$data = {
  readonly color: ProjectV2SingleSelectFieldOptionColor;
  readonly id: string;
  readonly name: string | null | undefined;
  readonly nameHTML: string | null | undefined;
  readonly optionId: string | null | undefined;
  readonly " $fragmentType": "SingleSelectFieldFragment";
};
export type SingleSelectFieldFragment$key = {
  readonly " $data"?: SingleSelectFieldFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SingleSelectFieldFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SingleSelectFieldFragment",
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
      "name": "optionId",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameHTML",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "color",
      "storageKey": null
    }
  ],
  "type": "ProjectV2ItemFieldSingleSelectValue",
  "abstractKey": null
};

(node as any).hash = "46251798d3a30836a6711ecaa3cc54e8";

export default node;
