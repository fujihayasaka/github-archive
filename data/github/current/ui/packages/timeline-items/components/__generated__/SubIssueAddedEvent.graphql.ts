/**
 * @generated SignedSource<<4a9de6e8c216087bae755a8db269e4df>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssueAddedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly subIssue: {
    readonly databaseId: number | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"IssueLink">;
  } | null | undefined;
  readonly " $fragmentType": "SubIssueAddedEvent";
};
export type SubIssueAddedEvent$key = {
  readonly " $data"?: SubIssueAddedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssueAddedEvent">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "databaseId",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "SubIssueAddedEvent",
  "selections": [
    (v0/*: any*/),
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
        }
      ],
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
      "concreteType": "Issue",
      "kind": "LinkedField",
      "name": "subIssue",
      "plural": false,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "IssueLink"
        },
        (v0/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "SubIssueAddedEvent",
  "abstractKey": null
};
})();

(node as any).hash = "6a27c73ef025222e54654739072c2d24";

export default node;
