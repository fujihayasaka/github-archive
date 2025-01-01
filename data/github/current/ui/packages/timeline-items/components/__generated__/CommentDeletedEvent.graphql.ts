/**
 * @generated SignedSource<<f314f24133c2e0c0726b3659f4b4163f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type CommentDeletedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly deletedCommentAuthor: {
    readonly login: string;
  } | null | undefined;
  readonly " $fragmentType": "CommentDeletedEvent";
};
export type CommentDeletedEvent$key = {
  readonly " $data"?: CommentDeletedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"CommentDeletedEvent">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "CommentDeletedEvent",
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
      "concreteType": null,
      "kind": "LinkedField",
      "name": "deletedCommentAuthor",
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
    }
  ],
  "type": "CommentDeletedEvent",
  "abstractKey": null
};

(node as any).hash = "60765ec10a7e0eb7ec5c8d4eca344b84";

export default node;
