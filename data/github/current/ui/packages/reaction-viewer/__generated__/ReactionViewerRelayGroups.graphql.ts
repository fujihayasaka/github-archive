/**
 * @generated SignedSource<<d8e071356d879b26b186791eedaf27aa>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type ReactionContent = "CONFUSED" | "EYES" | "HEART" | "HOORAY" | "LAUGH" | "ROCKET" | "THUMBS_DOWN" | "THUMBS_UP" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type ReactionViewerRelayGroups$data = {
  readonly reactionGroups: ReadonlyArray<{
    readonly content: ReactionContent;
    readonly reactors: {
      readonly nodes: ReadonlyArray<{
        readonly __typename: "Bot";
        readonly login: string;
      } | {
        readonly __typename: "Mannequin";
        readonly login: string;
      } | {
        readonly __typename: "Organization";
        readonly login: string;
      } | {
        readonly __typename: "User";
        readonly login: string;
      } | {
        // This will never be '%other', but we need some
        // value in case none of the concrete values match.
        readonly __typename: "%other";
      } | null | undefined> | null | undefined;
      readonly totalCount: number;
    };
    readonly viewerHasReacted: boolean;
  }> | null | undefined;
  readonly " $fragmentType": "ReactionViewerRelayGroups";
};
export type ReactionViewerRelayGroups$key = {
  readonly " $data"?: ReactionViewerRelayGroups$data;
  readonly " $fragmentSpreads": FragmentRefs<"ReactionViewerRelayGroups">;
};

const node: ReaderFragment = (function(){
var v0 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "login",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "__typename",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ReactionViewerRelayGroups",
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
          "kind": "ScalarField",
          "name": "viewerHasReacted",
          "storageKey": null
        },
        {
          "alias": null,
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 5
            }
          ],
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
            },
            {
              "alias": null,
              "args": null,
              "concreteType": null,
              "kind": "LinkedField",
              "name": "nodes",
              "plural": true,
              "selections": [
                {
                  "kind": "InlineFragment",
                  "selections": (v0/*: any*/),
                  "type": "User",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v0/*: any*/),
                  "type": "Bot",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v0/*: any*/),
                  "type": "Organization",
                  "abstractKey": null
                },
                {
                  "kind": "InlineFragment",
                  "selections": (v0/*: any*/),
                  "type": "Mannequin",
                  "abstractKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": "reactors(first:5)"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Reactable",
  "abstractKey": "__isReactable"
};
})();

(node as any).hash = "683f509bd79d5a4206eb49d13f947374";

export default node;
