/**
 * @generated SignedSource<<e8151762e12b0ddb4f2e46aaeac5dfbf>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssuePullRequestTitle$data = {
  readonly __typename: "Issue";
  readonly id: string;
  readonly labels: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly name: string;
      readonly " $fragmentSpreads": FragmentRefs<"Label">;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly number: number;
  readonly " $fragmentType": "IssuePullRequestTitle";
} | {
  readonly __typename: "PullRequest";
  readonly labels: {
    readonly nodes: ReadonlyArray<{
      readonly id: string;
      readonly name: string;
      readonly " $fragmentSpreads": FragmentRefs<"Label">;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly number: number;
  readonly " $fragmentType": "IssuePullRequestTitle";
} | {
  // This will never be '%other', but we need some
  // value in case none of the concrete values match.
  readonly __typename: "%other";
  readonly " $fragmentType": "IssuePullRequestTitle";
};
export type IssuePullRequestTitle$key = {
  readonly " $data"?: IssuePullRequestTitle$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssuePullRequestTitle">;
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
  "args": [
    {
      "kind": "Variable",
      "name": "first",
      "variableName": "labelPageSize"
    },
    {
      "kind": "Literal",
      "name": "orderBy",
      "value": {
        "direction": "ASC",
        "field": "NAME"
      }
    }
  ],
  "concreteType": "LabelConnection",
  "kind": "LinkedField",
  "name": "labels",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "Label",
      "kind": "LinkedField",
      "name": "nodes",
      "plural": true,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "Label"
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "name",
          "storageKey": null
        },
        (v0/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": 10,
      "kind": "LocalArgument",
      "name": "labelPageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssuePullRequestTitle",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    },
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
        (v1/*: any*/),
        (v2/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};
})();

(node as any).hash = "3cd31e92ffc08973d371b853b48191ae";

export default node;
