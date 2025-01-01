/**
 * @generated SignedSource<<3bbf1d9acb34019486473ca1a0ac9562>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ConvertedFromDraftEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly " $fragmentType": "ConvertedFromDraftEvent";
};
export type ConvertedFromDraftEvent$key = {
  readonly " $data"?: ConvertedFromDraftEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"ConvertedFromDraftEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ConvertedFromDraftEvent",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "createdAt",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "actor",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TimelineRowEventActor"
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "databaseId",
      "storageKey": null
    }
  ],
  "type": "ConvertedFromDraftEvent",
  "abstractKey": null
};

(node as any).hash = "3719925429eadd15091ec256d7d9c8fd";

export default node;
