/**
 * @generated SignedSource<<4b0c9a90f87d294721b93cf379ac92f1>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type MarkedAsDuplicateEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly canonical: {
    readonly id?: string;
    readonly number?: number;
    readonly " $fragmentSpreads": FragmentRefs<"IssueLink">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly id: string;
  readonly isCanonicalOfClosedDuplicate: boolean | null | undefined;
  readonly pendingUndo: boolean | null | undefined;
  readonly viewerCanUndo: boolean;
  readonly " $fragmentType": "MarkedAsDuplicateEvent";
};
export type MarkedAsDuplicateEvent$key = {
  readonly " $data"?: MarkedAsDuplicateEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"MarkedAsDuplicateEvent">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "IssueLink"
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "MarkedAsDuplicateEvent",
  "selections": [
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
      "concreteType": null,
      "kind": "LinkedField",
      "name": "canonical",
      "plural": false,
      "selections": [
        {
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/),
            (v1/*: any*/),
            (v2/*: any*/)
          ],
          "type": "Issue",
          "abstractKey": null
        },
        {
          "kind": "InlineFragment",
          "selections": [
            (v0/*: any*/),
            (v2/*: any*/),
            (v1/*: any*/)
          ],
          "type": "PullRequest",
          "abstractKey": null
        }
      ],
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isCanonicalOfClosedDuplicate",
      "storageKey": null
    },
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
      "name": "viewerCanUndo",
      "storageKey": null
    },
    (v1/*: any*/),
    {
      "kind": "ClientExtension",
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "pendingUndo",
          "storageKey": null
        }
      ]
    }
  ],
  "type": "MarkedAsDuplicateEvent",
  "abstractKey": null
};
})();

(node as any).hash = "cfb28297aa1d6a5ded340aa98ea9d68d";

export default node;
