/**
 * @generated SignedSource<<9858d03c64a498528f823fe7160f80fd>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SavedViewsShortcutsFragment$data = {
  readonly shortcuts: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly name: string;
      readonly query: string;
      readonly " $fragmentSpreads": FragmentRefs<"SavedViewRow">;
    } | null | undefined> | null | undefined;
    readonly totalCount: number;
  };
  readonly " $fragmentType": "SavedViewsShortcutsFragment";
};
export type SavedViewsShortcutsFragment$key = {
  readonly " $data"?: SavedViewsShortcutsFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"SavedViewsShortcutsFragment">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SavedViewsShortcutsFragment",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 25
        }
      ],
      "concreteType": "SearchShortcutConnection",
      "kind": "LinkedField",
      "name": "shortcuts",
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
          "concreteType": "SearchShortcut",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
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
              "name": "name",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "query",
              "storageKey": null
            },
            {
              "args": null,
              "kind": "FragmentSpread",
              "name": "SavedViewRow"
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "shortcuts(first:25)"
    }
  ],
  "type": "UserDashboard",
  "abstractKey": null
};

(node as any).hash = "9a49a46a5715f6ebf02954f58883658b";

export default node;
