/**
 * @generated SignedSource<<d7a63c7ef45456a391e5a796aff45d29>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarPrimaryQuery$data = {
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionFragment" | "FieldsSectionFragment" | "LabelsSectionFragment" | "MilestonesSectionFragment" | "OptionsSectionFragment" | "ProjectsSectionFragment" | "TypesSectionFragment">;
  readonly " $fragmentType": "IssueSidebarPrimaryQuery";
};
export type IssueSidebarPrimaryQuery$key = {
  readonly " $data"?: IssueSidebarPrimaryQuery$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueSidebarPrimaryQuery">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "allowedOwner"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueSidebarPrimaryQuery",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "AssigneesSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "LabelsSectionFragment"
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "allowedOwner",
          "variableName": "allowedOwner"
        }
      ],
      "kind": "FragmentSpread",
      "name": "ProjectsSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "MilestonesSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "OptionsSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TypesSectionFragment"
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "FieldsSectionFragment"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "dedc5f445c2698fbfc52de57413c66a9";

export default node;
