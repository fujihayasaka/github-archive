/**
 * @generated SignedSource<<4837e9b7ad7d6890635f17bb9fc6aa1a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LabeledEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly label: {
    readonly " $fragmentSpreads": FragmentRefs<"LabelData">;
  };
  readonly " $fragmentType": "LabeledEvent";
};
export type LabeledEvent$key = {
  readonly " $data"?: LabeledEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"LabeledEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "LabeledEvent",
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
      "concreteType": "Label",
      "kind": "LinkedField",
      "name": "label",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "LabelData"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "LabeledEvent",
  "abstractKey": null
};

(node as any).hash = "b7e2ce506173e4d9028a5365bafcd8bd";

export default node;
