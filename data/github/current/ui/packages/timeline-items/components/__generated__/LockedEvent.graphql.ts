/**
 * @generated SignedSource<<9848ca15c1c16ca331af4071d4b9e716>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type LockReason = "OFF_TOPIC" | "RESOLVED" | "SPAM" | "TOO_HEATED" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type LockedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly lockReason: LockReason | null | undefined;
  readonly " $fragmentType": "LockedEvent";
};
export type LockedEvent$key = {
  readonly " $data"?: LockedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"LockedEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "LockedEvent",
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
      "kind": "ScalarField",
      "name": "lockReason",
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
    }
  ],
  "type": "LockedEvent",
  "abstractKey": null
};

(node as any).hash = "5cd622162b89b270c4ae9e3b77be0625";

export default node;
