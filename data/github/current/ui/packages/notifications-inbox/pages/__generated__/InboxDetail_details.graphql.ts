/**
 * @generated SignedSource<<36a8c4c83c0d6dc7c072cddee8de3157>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type InboxDetail_details$data = {
  readonly id: string;
  readonly subject: {
    readonly __typename: "Issue";
    readonly id: string;
    readonly number: number;
    readonly repository: {
      readonly name: string;
      readonly owner: {
        readonly login: string;
      };
    };
  } | {
    // This will never be '%other', but we need some
    // value in case none of the concrete values match.
    readonly __typename: "%other";
  };
  readonly " $fragmentSpreads": FragmentRefs<"InboxHeader_notification">;
  readonly " $fragmentType": "InboxDetail_details";
};
export type InboxDetail_details$key = {
  readonly " $data"?: InboxDetail_details$data;
  readonly " $fragmentSpreads": FragmentRefs<"InboxDetail_details">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "InboxDetail_details",
  "selections": [
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "InboxHeader_notification"
    },
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "subject",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "__typename",
          "storageKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/),
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
            }
          ],
          "type": "Issue",
          "abstractKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "NotificationThread",
  "abstractKey": null
};
})();

(node as any).hash = "289900acc6857f82ad9263eab9fe1b28";

export default node;
