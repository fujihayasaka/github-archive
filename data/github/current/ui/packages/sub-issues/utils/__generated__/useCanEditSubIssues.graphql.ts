/**
 * @generated SignedSource<<2d45ab2af973d4e8fa4d18443d8b09e4>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type useCanEditSubIssues$data = {
  readonly repository: {
    readonly isArchived: boolean;
  };
  readonly viewerCanUpdateMetadata: boolean | null | undefined;
  readonly " $fragmentType": "useCanEditSubIssues";
};
export type useCanEditSubIssues$key = {
  readonly " $data"?: useCanEditSubIssues$data;
  readonly " $fragmentSpreads": FragmentRefs<"useCanEditSubIssues">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "useCanEditSubIssues",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanUpdateMetadata",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "isArchived",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "8431d46d0aee4f10f97387f59bb22f71";

export default node;
