/**
 * @generated SignedSource<<1ad1f799ab2b338d228c1d2f1b82ddc9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ActivityView_viewer$data = {
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
      "args": null,
      "kind": "FragmentSpread",
      "name": "Thread_viewer"
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "dba51eff57684cc8476bd29064c10a6a";

export default node;
