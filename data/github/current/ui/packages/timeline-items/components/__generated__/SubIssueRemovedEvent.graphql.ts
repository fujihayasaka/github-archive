/**
 * @generated SignedSource<<cba4639c53c94ba056406275957974d8>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SubIssueRemovedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly subIssue: {
    readonly databaseId: number | null | undefined;
    readonly " $fragmentSpreads": FragmentRefs<"IssueLink">;
  } | null | undefined;
  readonly " $fragmentType": "SubIssueRemovedEvent";
};
export type SubIssueRemovedEvent$key = {
  readonly " $data"?: SubIssueRemovedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"SubIssueRemovedEvent">;
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
  "name": "SubIssueRemovedEvent",
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
  "type": "SubIssueRemovedEvent",
  "abstractKey": null
};
})();

(node as any).hash = "0fe9d2b98241be788b327b4a8a55ad18";

export default node;
