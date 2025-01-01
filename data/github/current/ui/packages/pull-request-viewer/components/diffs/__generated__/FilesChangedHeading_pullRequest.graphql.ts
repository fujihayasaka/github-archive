/**
 * @generated SignedSource<<8486646c97aa6d00730c7200034867ea>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FilesChangedHeading_pullRequest$data = {
  readonly comparison: {
    readonly linesAdded: number;
    readonly linesDeleted: number;
  } | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"DiffViewSettingsButton_pullRequest">;
  readonly " $fragmentType": "FilesChangedHeading_pullRequest";
};
export type FilesChangedHeading_pullRequest$key = {
  readonly " $data"?: FilesChangedHeading_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"FilesChangedHeading_pullRequest">;
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
  "name": "FilesChangedHeading_pullRequest",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "DiffViewSettingsButton_pullRequest"
    },
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
          "kind": "ScalarField",
          "name": "linesAdded",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "linesDeleted",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};

(node as any).hash = "d827e1d20fe9ac663809fd31dc83d571";

export default node;
