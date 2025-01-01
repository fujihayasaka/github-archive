/**
 * @generated SignedSource<<0719c13e2385e36ead366d3a2d07ec64>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type ReactionContent = "CONFUSED" | "EYES" | "HEART" | "HOORAY" | "LAUGH" | "ROCKET" | "THUMBS_DOWN" | "THUMBS_UP" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type Reactions$data = {
  readonly reactionGroups: ReadonlyArray<{
    readonly content: ReactionContent;
    readonly reactors: {
      readonly totalCount: number;
    };
  }> | null | undefined;
  readonly " $fragmentType": "Reactions";
};
export type Reactions$key = {
  readonly " $data"?: Reactions$data;
  readonly " $fragmentSpreads": FragmentRefs<"Reactions">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "Reactions",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "ReactionGroup",
      "kind": "LinkedField",
      "name": "reactionGroups",
      "plural": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "content",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": "ReactorConnection",
          "kind": "LinkedField",
          "name": "reactors",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "totalCount",
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Reactable",
  "abstractKey": "__isReactable"
};

(node as any).hash = "74f8d34cc7d8c1ceb397b94750030f0d";

export default node;
