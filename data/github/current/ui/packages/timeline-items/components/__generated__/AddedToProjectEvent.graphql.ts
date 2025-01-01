/**
 * @generated SignedSource<<41af1d8389794e05dd35b195eee8c00a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type AddedToProjectEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly project: {
    readonly name: string;
    readonly url: string;
  } | null | undefined;
  readonly projectColumnName: string;
  readonly " $fragmentType": "AddedToProjectEvent";
};
export type AddedToProjectEvent$key = {
  readonly " $data"?: AddedToProjectEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"AddedToProjectEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "AddedToProjectEvent",
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
      "concreteType": "Project",
      "kind": "LinkedField",
      "name": "project",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "name",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "url",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "projectColumnName",
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
  "type": "AddedToProjectEvent",
  "abstractKey": null
};

(node as any).hash = "ba2e4fa4caa6228a08a1288a6b5e81df";

export default node;
