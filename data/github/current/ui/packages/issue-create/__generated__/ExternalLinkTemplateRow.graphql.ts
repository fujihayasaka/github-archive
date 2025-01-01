/**
 * @generated SignedSource<<cedda63ca5b8dbbb1fbfa948376a8427>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ExternalLinkTemplateRow$data = {
  readonly about: string;
  readonly name: string;
  readonly url: string;
  readonly " $fragmentType": "ExternalLinkTemplateRow";
};
export type ExternalLinkTemplateRow$key = {
  readonly " $data"?: ExternalLinkTemplateRow$data;
  readonly " $fragmentSpreads": FragmentRefs<"ExternalLinkTemplateRow">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ExternalLinkTemplateRow",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "about",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "name",
      "storageKey": null
    }
  ],
  "type": "RepositoryContactLink",
  "abstractKey": null
};

(node as any).hash = "89d8106fd30fe009b4d13c1f4908f32e";

export default node;
