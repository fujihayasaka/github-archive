/**
 * @generated SignedSource<<780f1cbcc2ef258302d312f8ec375ef9>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type HeaderViewer$data = {
  readonly number: number;
  readonly repository: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly titleHTML: string;
  readonly url: string;
  readonly viewerCanUpdateNext: boolean | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderMenu">;
  readonly " $fragmentType": "HeaderViewer";
};
export type HeaderViewer$key = {
  readonly " $data"?: HeaderViewer$data;
  readonly " $fragmentSpreads": FragmentRefs<"HeaderViewer">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "HeaderViewer",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "titleHTML",
      "storageKey": null
    },
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
      "name": "url",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanUpdateNext",
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
          "name": "name",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "owner",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "login",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "HeaderMenu"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "3cf3147bbe18ccb67717436d818f5d22";

export default node;
