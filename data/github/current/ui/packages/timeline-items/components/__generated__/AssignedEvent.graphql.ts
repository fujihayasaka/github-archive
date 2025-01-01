/**
 * @generated SignedSource<<4902f7ad89cb2b620d15e263f3d99054>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssignedEvent$data = {
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
  readonly " $fragmentType": "AssignedEvent";
};
export type AssignedEvent$key = {
  readonly " $data"?: AssignedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssignedEvent">;
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
  "name": "AssignedEvent",
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
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "TimelineRowEventActor"
        },
        (v0/*: any*/)
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
  "type": "AssignedEvent",
  "abstractKey": null
};
})();

(node as any).hash = "a8f2fa7634a679969efc39b7b8f2d616";

export default node;
