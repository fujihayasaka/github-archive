/**
 * @generated SignedSource<<783c14bc44518d444a4ee62665c6bae3>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeaderAuthor$data = {
  readonly login: string;
  readonly profileUrl: string | null | undefined;
  readonly " $fragmentType": "IssueBodyHeaderAuthor";
};
export type IssueBodyHeaderAuthor$key = {
  readonly " $data"?: IssueBodyHeaderAuthor$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderAuthor">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeaderAuthor",
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
      "args": null,
      "kind": "ScalarField",
      "name": "profileUrl",
      "storageKey": null
    }
  ],
  "type": "Actor",
  "abstractKey": "__isActor"
};

(node as any).hash = "18098578fa2042c3862894ceb62ea79b";

export default node;
