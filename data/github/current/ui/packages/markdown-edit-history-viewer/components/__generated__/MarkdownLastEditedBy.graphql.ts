/**
 * @generated SignedSource<<e4f1b17f43adc818b31247dbbab5ed6d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type MarkdownLastEditedBy$data = {
  readonly lastUserContentEdit: {
    readonly editor: {
      readonly login: string;
      readonly url: string;
    } | null | undefined;
  } | null | undefined;
  readonly viewerCanReadUserContentEdits: boolean;
  readonly " $fragmentType": "MarkdownLastEditedBy";
};
export type MarkdownLastEditedBy$key = {
  readonly " $data"?: MarkdownLastEditedBy$data;
  readonly " $fragmentSpreads": FragmentRefs<"MarkdownLastEditedBy">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MarkdownLastEditedBy",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanReadUserContentEdits",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "UserContentEdit",
      "kind": "LinkedField",
      "name": "lastUserContentEdit",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "editor",
          "plural": false,
          "selections": [
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
              "name": "login",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Comment",
  "abstractKey": "__isComment"
};

(node as any).hash = "bbab0cb2d43eeaaa0ed5b010868ec7f4";

export default node;
