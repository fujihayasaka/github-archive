/**
 * @generated SignedSource<<7af6761b9f483a8df7c8c98ed3dc4d32>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type FileConversationsButton_viewer$data = {
  readonly avatarUrl: string;
  readonly login: string;
  readonly " $fragmentType": "FileConversationsButton_viewer";
};
export type FileConversationsButton_viewer$key = {
  readonly " $data"?: FileConversationsButton_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"FileConversationsButton_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "FileConversationsButton_viewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "login",
      "storageKey": null
    },
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "size",
          "value": 48
        }
      ],
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": "avatarUrl(size:48)"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "aa429cd53af8016d4064521c3d199532";

export default node;
