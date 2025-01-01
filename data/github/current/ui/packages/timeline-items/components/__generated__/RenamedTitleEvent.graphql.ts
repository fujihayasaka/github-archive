/**
 * @generated SignedSource<<5e8014afad693316948e315dea9e15bb>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type RenamedTitleEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly currentTitle: string;
  readonly databaseId: number | null | undefined;
  readonly previousTitle: string;
  readonly " $fragmentType": "RenamedTitleEvent";
};
export type RenamedTitleEvent$key = {
  readonly " $data"?: RenamedTitleEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"RenamedTitleEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "RenamedTitleEvent",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "databaseId",
      "storageKey": null
    },
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
      "name": "currentTitle",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "previousTitle",
      "storageKey": null
    }
  ],
  "type": "RenamedTitleEvent",
  "abstractKey": null
};

(node as any).hash = "51c475b1e987f59acbc80c0754983081";

export default node;
