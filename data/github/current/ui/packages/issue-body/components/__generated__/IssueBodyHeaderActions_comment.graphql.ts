/**
 * @generated SignedSource<<d74b943d03d5f3f3caa516d53361fa87>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeaderActions_comment$data = {
  readonly body: string;
  readonly " $fragmentType": "IssueBodyHeaderActions_comment";
};
export type IssueBodyHeaderActions_comment$key = {
  readonly " $data"?: IssueBodyHeaderActions_comment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions_comment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeaderActions_comment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "body",
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
};

(node as any).hash = "e65d1b4543dae8f62c447cba44e163f1";

export default node;
