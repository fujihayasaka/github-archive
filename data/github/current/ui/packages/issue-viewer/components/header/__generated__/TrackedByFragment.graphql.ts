/**
 * @generated SignedSource<<1c2b13b42e309b7b10179dfe341a4c94>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type TrackedByFragment$data = {
  readonly trackedInIssues: {
    readonly nodes: ReadonlyArray<{
      readonly number: number;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly url: string;
    } | null | undefined> | null | undefined;
    readonly totalCount: number;
  };
  readonly " $fragmentType": "TrackedByFragment";
};
export type TrackedByFragment$key = {
  readonly " $data"?: TrackedByFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"TrackedByFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TrackedByFragment",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 10
        }
      ],
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "trackedInIssues",
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
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "number",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "url",
              "storageKey": null
            },
            {
              "alias": null,
              "args": [
                {
                  "kind": "Literal",
                  "name": "enableDuplicate",
                  "value": true
                }
              ],
              "kind": "ScalarField",
              "name": "stateReason",
              "storageKey": "stateReason(enableDuplicate:true)"
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
      "storageKey": "trackedInIssues(first:10)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "b589f0916eb19a849d943124e14d0651";

export default node;
