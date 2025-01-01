/**
 * @generated SignedSource<<e307aa89763a3d362a289d4183f064d8>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type LazyContributorFooter$data = {
  readonly codeOfConductFileUrl: string | null | undefined;
  readonly contributingFileUrl: string | null | undefined;
  readonly securityPolicyUrl: string | null | undefined;
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
    }
  ],
  "type": "Repository",
  "abstractKey": null
};

(node as any).hash = "d2a8c9eedc89aef8966e7d5129eb31ce";

export default node;
