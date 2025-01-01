/**
 * @generated SignedSource<<fdd69fd507f775d525d4e0f9a122d457>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueBodyHeaderActions_issue$data = {
  readonly title: string;
  readonly " $fragmentType": "IssueBodyHeaderActions_issue";
};
export type IssueBodyHeaderActions_issue$key = {
  readonly " $data"?: IssueBodyHeaderActions_issue$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueBodyHeaderActions_issue">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueBodyHeaderActions_issue",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "title",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "66886cc70956ce21a586e3af111c513a";

export default node;
