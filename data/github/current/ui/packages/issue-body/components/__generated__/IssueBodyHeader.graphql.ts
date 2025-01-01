/**
 * @generated SignedSource<<e622f88eb4622f21ad384071052c24fa>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeader$data = {
  readonly author: {
    readonly avatarUrl: string;
    readonly login: string;
    readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions" | "IssueBodyHeaderAuthor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly viewerDidAuthor: boolean;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions_comment">;
  readonly " $fragmentType": "IssueBodyHeader";
};
export type IssueBodyHeader$key = {
  readonly " $data"?: IssueBodyHeader$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeader">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeader",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "IssueBodyHeaderActions_comment"
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
      "name": "viewerDidAuthor",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "author",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueBodyHeaderAuthor"
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueBodyHeaderActions"
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "avatarUrl",
          "storageKey": null
        },
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
  "type": "Comment",
  "abstractKey": "__isComment"
};

(node as any).hash = "e00f03cabfddb341093ded2bb503aeea";

export default node;
