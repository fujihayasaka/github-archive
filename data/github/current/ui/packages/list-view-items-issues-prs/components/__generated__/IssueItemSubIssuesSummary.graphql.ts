/**
 * @generated SignedSource<<ba17f7267263517787cdc8bf785f9000>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueItemSubIssuesSummary$data = {
  readonly subIssuesSummary: {
    readonly completed: number;
    readonly percentCompleted: number;
    readonly total: number;
  };
  readonly " $fragmentType": "IssueItemSubIssuesSummary";
};
export type IssueItemSubIssuesSummary$key = {
  readonly " $data"?: IssueItemSubIssuesSummary$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueItemSubIssuesSummary">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueItemSubIssuesSummary",
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
          "name": "completed",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "percentCompleted",
          "storageKey": null
        },
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

(node as any).hash = "69d927a8cc29fe0a0e03b982885c9f3a";

export default node;
