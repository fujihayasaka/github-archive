/**
 * @generated SignedSource<<2be34ba24f215c828045693c15904d9a>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type SubscriptionSectionFragment$data = {
  readonly id: string;
  readonly threadSubscriptionChannel: string | null | undefined;
  readonly " $fragmentType": "SubscriptionSectionFragment";
};
export type SubscriptionSectionFragment$key = {
  readonly " $data"?: SubscriptionSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubscriptionSectionFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubscriptionSectionFragment",
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
      "name": "threadSubscriptionChannel",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "960bdbc3185068222a1e993ec20af0e7";

export default node;
