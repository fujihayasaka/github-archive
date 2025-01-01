/**
 * @generated SignedSource<<82a79f0ce911a8eaf3e97b35e60213a9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type BlobActionsMenu_pullRequest$data = {
  readonly baseRepository: {
    readonly nameWithOwner: string;
  } | null | undefined;
  readonly headRefName: string;
  readonly headRepository: {
    readonly nameWithOwner: string;
  } | null | undefined;
  readonly number: number;
  readonly viewerCanEditFiles: boolean;
  readonly " $fragmentType": "BlobActionsMenu_pullRequest";
};
export type BlobActionsMenu_pullRequest$key = {
  readonly " $data"?: BlobActionsMenu_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"BlobActionsMenu_pullRequest">;
};

const node: ReaderFragment = (function(){
var v0 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "nameWithOwner",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "BlobActionsMenu_pullRequest",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "headRefName",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "headRepository",
      "plural": false,
      "selections": (v0/*: any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "baseRepository",
      "plural": false,
      "selections": (v0/*: any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanEditFiles",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};
})();

(node as any).hash = "7750e814c88b53997e197c149265c5a1";

export default node;
