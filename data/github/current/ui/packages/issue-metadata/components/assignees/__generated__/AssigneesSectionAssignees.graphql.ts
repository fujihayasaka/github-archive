/**
 * @generated SignedSource<<7a1f2dc1ad3365997039232a303fc3de>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneesSectionAssignees$data = {
  readonly assignedActors: {
    readonly nodes: ReadonlyArray<{
      readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
    } | null | undefined> | null | undefined;
  };
  readonly " $fragmentType": "AssigneesSectionAssignees";
};
export type AssigneesSectionAssignees$key = {
  readonly " $data"?: AssigneesSectionAssignees$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionAssignees">;
};

const node: ReaderFragment = {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "AssigneesSectionAssignees",
  "selections": [
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 20
        }
      ],
      "concreteType": "AssigneeConnection",
      "kind": "LinkedField",
      "name": "assignedActors",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
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
          "storageKey": null
        }
      ],
      "storageKey": "assignedActors(first:20)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};

(node as any).hash = "282d86dd9147347d0da93f8017dcd0a3";

export default node;
