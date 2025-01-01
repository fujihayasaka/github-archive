/**
 * @generated SignedSource<<07905c83e1defba4227ffd7129d3f8c6>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type PullRequestItemHeadCommit$data = {
  readonly headCommit: {
    readonly commit: {
      readonly id: string;
      readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatus">;
    };
  } | null | undefined;
  readonly " $fragmentType": "PullRequestItemHeadCommit";
};
export type PullRequestItemHeadCommit$key = {
  readonly " $data"?: PullRequestItemHeadCommit$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestItemHeadCommit">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "PullRequestItemHeadCommit",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "PullRequestCommit",
      "kind": "LinkedField",
      "name": "headCommit",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Commit",
          "kind": "LinkedField",
          "name": "commit",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "id",
              "storageKey": null
            },
            {
              "args": null,
              "kind": "FragmentSpread",
              "name": "CheckRunStatus"
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "fd277c6401a8f4dcc071cc6026716196";

export default node;
