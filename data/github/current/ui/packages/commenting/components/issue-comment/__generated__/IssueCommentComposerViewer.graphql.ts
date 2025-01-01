/**
 * @generated SignedSource<<5cea5b5b23a9609aa8ab64cba74490b8>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueCommentComposerViewer$data = {
  readonly avatarUrl: string;
  readonly id: string;
  readonly login: string;
  readonly " $fragmentType": "IssueCommentComposerViewer";
};
export type IssueCommentComposerViewer$key = {
  readonly " $data"?: IssueCommentComposerViewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueCommentComposerViewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueCommentComposerViewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
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
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "a3fc475b7d098c92deda0596a5d5a864";

export default node;
