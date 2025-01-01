/**
 * @generated SignedSource<<99ee41273b6d887549ff6c7b53cd2279>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneCreateFormRepositoryQuery$data = {
  readonly nameWithOwner: string;
  readonly viewerCanPush: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneFormRepositoryQueryInternal">;
  readonly " $fragmentType": "MilestoneCreateFormRepositoryQuery";
};
export type MilestoneCreateFormRepositoryQuery$key = {
  readonly " $data"?: MilestoneCreateFormRepositoryQuery$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneCreateFormRepositoryQuery">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestoneCreateFormRepositoryQuery",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanPush",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestoneFormRepositoryQueryInternal"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "4436584437a09ba2611e78aa4dba1852";

export default node;
