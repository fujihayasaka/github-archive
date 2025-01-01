/**
 * @generated SignedSource<<d1f926a3a296ecefc3c01eef82668667>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ClosedByPullRequestsReferences$data = {
  readonly closedByPullRequestsReferences: {
    readonly totalCount: number;
  } | null | undefined;
  readonly " $fragmentType": "ClosedByPullRequestsReferences";
};
export type ClosedByPullRequestsReferences$key = {
  readonly " $data"?: ClosedByPullRequestsReferences$data;
  readonly " $fragmentSpreads": FragmentRefs<"ClosedByPullRequestsReferences">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": 0,
      "kind": "LocalArgument",
      "name": "first"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "ClosedByPullRequestsReferences",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "first",
          "variableName": "first"
        },
        {
          "kind": "Literal",
          "name": "includeClosedPrs",
          "value": true
        }
      ],
      "concreteType": "PullRequestConnection",
      "kind": "LinkedField",
      "name": "closedByPullRequestsReferences",
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

(node as any).hash = "d13c832969ca720e1f332e81bbc80289";

export default node;
