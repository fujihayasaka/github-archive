/**
 * @generated SignedSource<<39b063116efdeb5e75f21c706350149f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueFormRow$data = {
  readonly description: string | null | undefined;
  readonly filename: string;
  readonly name: string;
  readonly " $fragmentType": "IssueFormRow";
};
export type IssueFormRow$key = {
  readonly " $data"?: IssueFormRow$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueFormRow">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueFormRow",
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
      "name": "description",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "filename",
      "storageKey": null
    }
  ],
  "type": "IssueForm",
  "abstractKey": null
};

(node as any).hash = "4707734c7aff8e836f17a948f0fc6e8d";

export default node;
