/**
 * @generated SignedSource<<f9d1843bed1e51f098a0a64bd3fe4afd>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PinnedIssues$data = {
  readonly id: string;
  readonly pinnedIssues: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly issue: {
        readonly id: string;
        readonly title: string;
        readonly " $fragmentSpreads": FragmentRefs<"PinnedIssueIssue">;
      };
    } | null | undefined> | null | undefined;
    readonly totalCount: number;
  } | null | undefined;
  readonly viewerCanPinIssues: boolean;
  readonly " $fragmentType": "PinnedIssues";
};
export type PinnedIssues$key = {
  readonly " $data"?: PinnedIssues$data;
  readonly " $fragmentSpreads": FragmentRefs<"PinnedIssues">;
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
  "name": "PinnedIssues",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 3
        }
      ],
      "concreteType": "PinnedIssueConnection",
      "kind": "LinkedField",
      "name": "pinnedIssues",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "PinnedIssue",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            (v0/*: any*/),
            {
              "alias": null,
              "args": null,
              "concreteType": "Issue",
              "kind": "LinkedField",
              "name": "issue",
              "plural": false,
              "selections": [
                (v0/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "title",
                  "storageKey": null
                },
                {
                  "args": null,
                  "kind": "FragmentSpread",
                  "name": "PinnedIssueIssue"
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "totalCount",
          "storageKey": null
        }
      ],
      "storageKey": "pinnedIssues(first:3)"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPinIssues",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
})();

(node as any).hash = "6f99e78aa98c45e24d83e282f516fea3";

export default node;
