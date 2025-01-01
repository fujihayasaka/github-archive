/**
 * @generated SignedSource<<42ddd9dc2fd7b0e22d54880224423beb>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type LazyContributorFooter$data = {
  readonly codeOfConductFileUrl: string | null | undefined;
  readonly contributingFileUrl: string | null | undefined;
  readonly securityPolicyUrl: string | null | undefined;
  readonly supportFileUrl: string | null | undefined;
  readonly " $fragmentType": "LazyContributorFooter";
};
export type LazyContributorFooter$key = {
  readonly " $data"?: LazyContributorFooter$data;
  readonly " $fragmentSpreads": FragmentRefs<"LazyContributorFooter">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "LazyContributorFooter",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "codeOfConductFileUrl",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "securityPolicyUrl",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "contributingFileUrl",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "supportFileUrl",
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "a2fe72eb7ec1d9cd1393d0645985a492";

export default node;
