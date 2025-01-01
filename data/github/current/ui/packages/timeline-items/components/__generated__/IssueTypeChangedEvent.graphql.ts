/**
 * @generated SignedSource<<5e28d4a9602780d98a9aa71d3538779b>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueTypeColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type IssueTypeChangedEvent$data = {
  readonly actor: {
    readonly " $fragmentSpreads": FragmentRefs<"TimelineRowEventActor">;
  } | null | undefined;
  readonly createdAt: string;
  readonly databaseId: number | null | undefined;
  readonly issueType: {
    readonly color: IssueTypeColor;
    readonly name: string;
  } | null | undefined;
  readonly prevIssueType: {
    readonly color: IssueTypeColor;
    readonly name: string;
  } | null | undefined;
  readonly " $fragmentType": "IssueTypeChangedEvent";
};
export type IssueTypeChangedEvent$key = {
  readonly " $data"?: IssueTypeChangedEvent$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTypeChangedEvent">;
};

const node: ReaderFragment = (function(){
var v0 = [
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
    "name": "color",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTypeChangedEvent",
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
      "concreteType": "IssueType",
      "kind": "LinkedField",
      "name": "issueType",
      "plural": false,
      "selections": (v0/*: any*/),
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "IssueType",
      "kind": "LinkedField",
      "name": "prevIssueType",
      "plural": false,
      "selections": (v0/*: any*/),
      "storageKey": null
    }
  ],
  "type": "IssueTypeChangedEvent",
  "abstractKey": null
};
})();

(node as any).hash = "ff78cef208baee819e716cf0308f130a";

export default node;
