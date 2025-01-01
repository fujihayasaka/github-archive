/**
 * @generated SignedSource<<946f1fc37601c73958c9c3c93dd9322b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type useHasSubIssues$data = {
  readonly subIssuesConnection: {
    readonly totalCount: number;
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
      "alias": "subIssuesConnection",
      "args": null,
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "subIssues",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "totalCount",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "da209164b17ccab35ef2926feef98bae";

export default node;
