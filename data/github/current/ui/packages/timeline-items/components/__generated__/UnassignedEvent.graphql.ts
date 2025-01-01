/**
 * @generated SignedSource<<b55ed9621a8a89caa7ee49a7c50ece34>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type UnassignedEvent$data = {
  readonly actor: {
    readonly login: string;
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly assignee: {
    readonly login?: string;
    readonly " $fragmentSpreads": FragmentRefs<"AssignmentEventAssignee">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly " $fragmentType": "UnassignedEvent";
};
export type UnassignedEvent$key = {
  readonly " $data"?: UnassignedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"UnassignedEvent">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "login",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "UnassignedEvent",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "databaseId",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "createdAt",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "actor",
      "plural": false,
      "selections": [
        (v0/*: any*/),
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TimelineRowEventActor"
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "assignee",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "AssignmentEventAssignee"
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/)
          ],
          "type": "Actor",
          "abstractKey": "__isActor"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "UnassignedEvent",
  "abstractKey": null
};
})();

(node as any).hash = "ba2c5c9b4cc41d8585bad101a6f58f30";

export default node;
