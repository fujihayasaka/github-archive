/**
 * @generated SignedSource<<b8a3e676f6361f8da7e58fd6276f99fb>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueOrPullRequestUnreadIndicator$data = {
  readonly __typename: "Issue";
  readonly isReadByViewer: boolean | null | undefined;
  readonly " $fragmentType": "IssueOrPullRequestUnreadIndicator";
} | {
  readonly __typename: "PullRequest";
  readonly isReadByViewer: boolean | null | undefined;
  readonly " $fragmentType": "IssueOrPullRequestUnreadIndicator";
} | {
  // This will never be '%other', but we need some
  // value in case none of the concrete values match.
  readonly __typename: "%other";
  readonly " $fragmentType": "IssueOrPullRequestUnreadIndicator";
};
export type IssueOrPullRequestUnreadIndicator$key = {
  readonly " $data"?: IssueOrPullRequestUnreadIndicator$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueOrPullRequestUnreadIndicator">;
};

const node: ReaderFragment = (function(){
var v0 = [
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "isReadByViewer",
    "storageKey": null
  }
];
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueOrPullRequestUnreadIndicator",
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
      "selections": (v0/*: any*/),
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": (v0/*: any*/),
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};
})();

(node as any).hash = "691d1fd40629826d5b45aaffeb927341";

export default node;
