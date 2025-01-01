/**
 * @generated SignedSource<<545b4556e842afacf4a470cae4a277a2>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MilestoneActions$data = {
  readonly milestone: {
    readonly number: number;
    readonly title: string;
    readonly " $fragmentSpreads": FragmentRefs<"MilestoneTitle" | "ToggleMilestoneState">;
  } | null | undefined;
  readonly name: string;
  readonly owner: {
    readonly login: string;
  };
  readonly viewerCanPush: boolean;
  readonly " $fragmentType": "MilestoneActions";
};
export type MilestoneActions$key = {
  readonly " $data"?: MilestoneActions$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestoneActions">;
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
  "name": "MilestoneActions",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Variable",
          "name": "number",
          "variableName": "number"
        }
      ],
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "ToggleMilestoneState"
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "MilestoneTitle"
        },
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
          "name": "title",
          "storageKey": null
        }
      ],
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
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "owner",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "login",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "4c04143e376497bc1a37d2218000a808";

export default node;
