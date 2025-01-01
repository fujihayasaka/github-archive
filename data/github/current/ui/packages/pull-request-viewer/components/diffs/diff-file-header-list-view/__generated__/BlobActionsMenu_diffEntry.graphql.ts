/**
 * @generated SignedSource<<5bd43ac6bc57a8bed6f3401482f01c6b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type PatchStatus = "ADDED" | "CHANGED" | "COPIED" | "DELETED" | "MODIFIED" | "RENAMED" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type BlobActionsMenu_diffEntry$data = {
  readonly isBinary: boolean;
  readonly isLfsPointer: boolean;
  readonly isSubmodule: boolean;
  readonly oid: string;
  readonly path: string;
  readonly status: PatchStatus;
  readonly " $fragmentType": "BlobActionsMenu_diffEntry";
};
export type BlobActionsMenu_diffEntry$key = {
  readonly " $data"?: BlobActionsMenu_diffEntry$data;
  readonly " $fragmentSpreads": FragmentRefs<"BlobActionsMenu_diffEntry">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "BlobActionsMenu_diffEntry",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "path",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "oid",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "status",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isSubmodule",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isBinary",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isLfsPointer",
      "storageKey": null
    }
  ],
  "type": "PullRequestDiffEntry",
  "abstractKey": null
};

(node as any).hash = "b5315606dde11188bd7392f9e4af7ce9";

export default node;
