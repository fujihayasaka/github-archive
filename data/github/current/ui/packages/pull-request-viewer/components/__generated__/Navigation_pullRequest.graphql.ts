/**
 * @generated SignedSource<<aa139ea02cf93bcb4caf798e9ea8443a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type Navigation_pullRequest$data = {
  readonly comparison: {
    readonly summary: ReadonlyArray<{
      readonly __typename: "PullRequestSummaryDelta";
    }> | null | undefined;
  } | null | undefined;
  readonly " $fragmentType": "Navigation_pullRequest";
};
export type Navigation_pullRequest$key = {
  readonly " $data"?: Navigation_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"Navigation_pullRequest">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "kind": "RootArgument",
      "name": "endOid"
    },
    {
      "kind": "RootArgument",
      "name": "singleCommitOid"
    },
    {
      "kind": "RootArgument",
      "name": "startOid"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "Navigation_pullRequest",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "endOid",
          "variableName": "endOid"
        },
        {
          "kind": "Variable",
          "name": "singleCommitOid",
          "variableName": "singleCommitOid"
        },
        {
          "kind": "Variable",
          "name": "startOid",
          "variableName": "startOid"
        }
      ],
      "concreteType": "PullRequestComparison",
      "kind": "LinkedField",
      "name": "comparison",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "PullRequestSummaryDelta",
          "kind": "LinkedField",
          "name": "summary",
          "plural": true,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "__typename",
              "storageKey": null
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

(node as any).hash = "9344b2cbd9f1c4d55647914f9ba2d1b7";

export default node;
