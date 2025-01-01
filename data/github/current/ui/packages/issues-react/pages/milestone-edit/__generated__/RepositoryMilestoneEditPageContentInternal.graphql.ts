/**
 * @generated SignedSource<<d531e7d2fcbabd7efcf77facf355a2ee>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RepositoryMilestoneEditPageContentInternal$data = {
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneEditFormRepositoryQuery">;
  readonly " $fragmentType": "RepositoryMilestoneEditPageContentInternal";
};
export type RepositoryMilestoneEditPageContentInternal$key = {
  readonly " $data"?: RepositoryMilestoneEditPageContentInternal$data;
  readonly " $fragmentSpreads": FragmentRefs<"RepositoryMilestoneEditPageContentInternal">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "number"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "RepositoryMilestoneEditPageContentInternal",
  "selections": [
    {
      "args": [
        {
          "kind": "Variable",
          "name": "number",
          "variableName": "number"
        }
      ],
      "kind": "FragmentSpread",
      "name": "MilestoneEditFormRepositoryQuery"
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "ff932bfcc382dda2e87c2a3243a08062";

export default node;
