/**
 * @generated SignedSource<<2087411d0109b6fade25e636ab0848e6>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
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
