/**
 * @generated SignedSource<<76dd99a5fcbf2d53cda34deab8a79d44>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useHasSubIssues$data = {
  readonly subIssuesSummary: {
    readonly total: number;
  };
  readonly " $fragmentType": "useHasSubIssues";
};
export type useHasSubIssues$key = {
  readonly " $data"?: useHasSubIssues$data;
  readonly " $fragmentSpreads": FragmentRefs<"useHasSubIssues">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "useHasSubIssues",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "SubIssuesSummary",
      "kind": "LinkedField",
      "name": "subIssuesSummary",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "total",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "cb7257c941f0b0b94afebec284c04fdb";

export default node;
