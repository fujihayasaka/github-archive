/**
 * @generated SignedSource<<c9e97dea4485fdd09e51edf7897899ec>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTemplateRow$data = {
  readonly about: string | null | undefined;
  readonly filename: string;
  readonly name: string;
  readonly " $fragmentType": "IssueTemplateRow";
};
export type IssueTemplateRow$key = {
  readonly " $data"?: IssueTemplateRow$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTemplateRow">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTemplateRow",
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
      "name": "about",
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
  "type": "IssueTemplate",
  "abstractKey": null
};

(node as any).hash = "2047157ce521e245c1030871b4d976b7";

export default node;
