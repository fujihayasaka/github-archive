/**
 * @generated SignedSource<<09fa9770a14b6e311561e44ef0ae831f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type MilestonedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly milestone: {
    readonly url: string;
  } | null | undefined;
  readonly milestoneTitle: string;
  readonly " $fragmentType": "MilestonedEvent";
};
export type MilestonedEvent$key = {
  readonly " $data"?: MilestonedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"MilestonedEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MilestonedEvent",
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
      "name": "milestoneTitle",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Milestone",
      "kind": "LinkedField",
      "name": "milestone",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "url",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "MilestonedEvent",
  "abstractKey": null
};

(node as any).hash = "81a3a898b155f065ca3d228b91ed14a3";

export default node;
