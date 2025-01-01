/**
 * @generated SignedSource<<94d07e70acf3da5c990ba75121f2ee86>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssuesListView$data = {
  readonly id: string;
  readonly repository: {
    readonly name: string;
  };
  readonly subIssues: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListItem">;
    } | null | undefined> | null | undefined;
  };
  readonly " $fragmentSpreads": FragmentRefs<"useSubIssuesSummary">;
  readonly " $fragmentType": "SubIssuesListView";
};
export type SubIssuesListView$key = {
  readonly " $data"?: SubIssuesListView$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssuesListView">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssuesListView",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "name",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 100
        }
      ],
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "subIssues",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Issue",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            (v0/*: any*/),
            {
              "args": null,
              "kind": "FragmentSpread",
              "name": "SubIssuesListItem"
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "subIssues(first:100)"
    },
    {
      "args": [
        {
          "kind": "Literal",
          "name": "fetchSubIssues",
          "value": true
        }
      ],
      "kind": "FragmentSpread",
      "name": "useSubIssuesSummary"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "b30f0f8a4b70acd5c66207b059fb8e6d";

export default node;
