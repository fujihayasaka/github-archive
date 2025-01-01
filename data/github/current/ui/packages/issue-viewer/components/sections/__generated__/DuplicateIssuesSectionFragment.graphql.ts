/**
 * @generated SignedSource<<baba6f375f96d5ace1c7bff4f45d90bf>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueState = "CLOSED" | "OPEN" | "%future added value";
export type IssueStateReason = "COMPLETED" | "DUPLICATE" | "NOT_PLANNED" | "REOPENED" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type DuplicateIssuesSectionFragment$data = {
  readonly duplicateIssues: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly number: number;
      readonly repository: {
        readonly nameWithOwner: string;
      };
      readonly state: IssueState;
      readonly stateReason: IssueStateReason | null | undefined;
      readonly title: string;
      readonly url: string;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly id: string;
  readonly number: number;
  readonly repository: {
    readonly nameWithOwner: string;
  };
  readonly url: string;
  readonly " $fragmentType": "DuplicateIssuesSectionFragment";
};
export type DuplicateIssuesSectionFragment$key = {
  readonly " $data"?: DuplicateIssuesSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"DuplicateIssuesSectionFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "url",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "concreteType": "Repository",
  "kind": "LinkedField",
  "name": "repository",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "nameWithOwner",
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "DuplicateIssuesSectionFragment",
  "selections": [
    (v0/*: any*/),
    (v1/*: any*/),
    (v2/*: any*/),
    (v3/*: any*/),
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 3
        }
      ],
      "concreteType": "IssueConnection",
      "kind": "LinkedField",
      "name": "duplicateIssues",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "Issue",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            (v0/*: any*/),
            (v1/*: any*/),
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "title",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "state",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "stateReason",
              "storageKey": null
            },
            (v2/*: any*/),
            (v3/*: any*/)
          ],
          "storageKey": null
        }
      ],
      "storageKey": "duplicateIssues(first:3)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "c28cf5382ecc5de4cf01626e7c9def8a";

export default node;
