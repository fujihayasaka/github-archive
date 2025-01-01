/**
 * @generated SignedSource<<10d6a7824a550582eba91e4ba57ee3fb>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueSidebarPrimaryQuery$data = {
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionFragment" | "LabelsSectionFragment" | "MilestonesSectionFragment" | "OptionsSectionFragment" | "ProjectsSectionFragment" | "TypesSectionFragment">;
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
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "78c464819a0d44c7c2391810c45a7b93";

export default node;
