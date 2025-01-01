/**
 * @generated SignedSource<<cdb2561f1b1aadb0d613ffb0fabb0b0d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type MentionedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly " $fragmentType": "MentionedEvent";
};
export type MentionedEvent$key = {
  readonly " $data"?: MentionedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"MentionedEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MentionedEvent",
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
      "kind": "ScalarField",
      "name": "databaseId",
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
  "type": "MentionedEvent",
  "abstractKey": null
};

(node as any).hash = "2c24d4c180d9855e7f633b2541aa9d07";

export default node;
