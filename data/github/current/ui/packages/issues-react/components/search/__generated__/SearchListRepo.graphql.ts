/**
 * @generated SignedSource<<92f83d2ae7365285cd061bcdc630a8b1>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchListRepo$data = {
  readonly isArchived: boolean;
  readonly isDisabled: boolean;
  readonly isLocked: boolean;
  readonly viewerCanPush: boolean;
  readonly " $fragmentType": "SearchListRepo";
};
export type SearchListRepo$key = {
  readonly " $data"?: SearchListRepo$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchListRepo">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SearchListRepo",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isDisabled",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isLocked",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isArchived",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "c694b15941f159951586b7320797a8e4";

export default node;
