/**
 * @generated SignedSource<<3a3780603bb91e8e6e51782024d713f6>>
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
  readonly isInOrganization: boolean;
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
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isInOrganization",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "f65187d282f8f58f706a2eabbfe6075b";

export default node;
