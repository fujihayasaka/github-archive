/**
 * @generated SignedSource<<740fe9f8adf1227d76af154547bc3cdc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ParticipantFragment$data = {
  readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
  readonly " $fragmentType": "ParticipantFragment";
};
export type ParticipantFragment$key = {
  readonly " $data"?: ParticipantFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ParticipantFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ParticipantFragment",
  "selections": [
    {
      "kind": "InlineDataFragmentSpread",
      "name": "AssigneePickerAssignee",
      "selections": [
        {
          "kind": "InlineFragment",
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "__typename",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "id",
              "storageKey": null
            },
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
              "name": "name",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "profileResourcePath",
              "storageKey": null
            },
            {
              "alias": null,
              "args": [
                {
                  "kind": "Literal",
                  "name": "size",
                  "value": 64
                }
              ],
              "kind": "ScalarField",
              "name": "avatarUrl",
              "storageKey": "avatarUrl(size:64)"
            },
            {
              "kind": "InlineFragment",
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "isCopilot",
                  "storageKey": null
                }
              ],
              "type": "Bot",
              "abstractKey": null
            }
          ],
          "type": "Actor",
          "abstractKey": "__isActor"
        }
      ],
      "args": null,
      "argumentDefinitions": []
    }
  ],
  "type": "User",
  "abstractKey": null
};

(node as any).hash = "16e1de1ea70e67fb233b6a8edf20f284";

export default node;
