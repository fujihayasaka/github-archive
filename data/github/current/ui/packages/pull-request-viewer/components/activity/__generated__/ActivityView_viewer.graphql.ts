/**
 * @generated SignedSource<<f0f175dc811b87f29cb8de9c6775c090>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ActivityView_viewer$data = {
  readonly avatarUrl: string;
  readonly login: string;
  readonly " $fragmentSpreads": FragmentRefs<"Thread_viewer">;
  readonly " $fragmentType": "ActivityView_viewer";
};
export type ActivityView_viewer$key = {
  readonly " $data"?: ActivityView_viewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"ActivityView_viewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ActivityView_viewer",
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
      "name": "avatarUrl",
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "Thread_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "d12eed28a44799575c5f7cca99b35a05";

export default node;
