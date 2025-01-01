/**
 * @generated SignedSource<<b630a0565d4b6cb4f143597ba7037f75>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchBarCurrentViewFragment$data = {
  readonly id: string;
  readonly name: string;
  readonly query: string;
  readonly scopingRepository: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  } | null | undefined;
  readonly " $fragmentType": "SearchBarCurrentViewFragment";
};
export type SearchBarCurrentViewFragment$key = {
  readonly " $data"?: SearchBarCurrentViewFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SearchBarCurrentViewFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SearchBarCurrentViewFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "query",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "scopingRepository",
      "plural": false,
      "selections": [
        (v0/*: any*/),
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
  "type": "Shortcutable",
  "abstractKey": "__isShortcutable"
};
})();

(node as any).hash = "9c50d63e7c8b908e123ab49c4f0f99ed";

export default node;
