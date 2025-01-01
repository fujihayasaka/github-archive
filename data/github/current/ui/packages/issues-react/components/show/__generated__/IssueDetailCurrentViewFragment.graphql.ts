/**
 * @generated SignedSource<<20828854a7dd80860dd09819b95a48af>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IssueDetailCurrentViewFragment$data = {
  readonly name: string;
  readonly query: string;
  readonly " $fragmentType": "IssueDetailCurrentViewFragment";
};
export type IssueDetailCurrentViewFragment$key = {
  readonly " $data"?: IssueDetailCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueDetailCurrentViewFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueDetailCurrentViewFragment",
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
      "name": "query",
      "storageKey": null
    }
  ],
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};

(node as any).hash = "2c8ca9d1a4c7011b9735fb27e282abab";

export default node;
