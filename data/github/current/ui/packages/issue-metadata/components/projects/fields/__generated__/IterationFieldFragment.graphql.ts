/**
 * @generated SignedSource<<9f71ead45043d3fc332a2a1a7c29f48c>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IterationFieldFragment$data = {
  readonly duration: number;
  readonly field: {
    readonly " $fragmentSpreads": FragmentRefs<"IterationFieldConfigFragment">;
  };
  readonly iterationId: string;
  readonly startDate: any;
  readonly title: string;
  readonly titleHTML: string;
  readonly " $fragmentType": "IterationFieldFragment";
};
export type IterationFieldFragment$key = {
  readonly " $data"?: IterationFieldFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IterationFieldFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IterationFieldFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "iterationId",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "title",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "titleHTML",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "startDate",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "duration",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "field",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IterationFieldConfigFragment"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "ProjectV2ItemFieldIterationValue",
  "abstractKey": null
};

(node as any).hash = "57212d5c33092763cd6c9ea8afef0615";

export default node;
