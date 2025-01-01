/**
 * @generated SignedSource<<79aa5b47caf998c69d5ae8b19274b31c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeItemMenuItem$data = {
  readonly id: string;
  readonly isEnabled: boolean;
  readonly name: string;
  readonly " $fragmentType": "IssueTypeItemMenuItem";
};
export type IssueTypeItemMenuItem$key = {
  readonly " $data"?: IssueTypeItemMenuItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTypeItemMenuItem">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTypeItemMenuItem",
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
      "name": "isEnabled",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "IssueType",
  "abstractKey": null
};

(node as any).hash = "aa193769cf045e524584317eb9c136b9";

export default node;
