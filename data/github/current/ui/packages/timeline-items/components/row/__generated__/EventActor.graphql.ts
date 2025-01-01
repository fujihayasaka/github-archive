/**
 * @generated SignedSource<<558a1a63b11d80ae7dd813dcd1b866ff>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type EventActor$data = {
  readonly __typename: string;
  readonly avatarUrl: string;
  readonly login: string;
  readonly " $fragmentType": "EventActor";
};
export type EventActor$key = {
  readonly " $data"?: EventActor$data;
  readonly " $fragmentSpreads": FragmentRefs<"EventActor">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "EventActor",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "size",
          "value": 64
        }
      ],
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": "avatarUrl(size:64)"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    }
  ],
  "type": "Actor",
  "abstractKey": "__isActor"
};

(node as any).hash = "34a138098a67488e743b4d074650115f";

export default node;
