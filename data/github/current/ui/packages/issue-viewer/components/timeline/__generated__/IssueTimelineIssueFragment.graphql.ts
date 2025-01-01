/**
 * @generated SignedSource<<86c45fc4534ac9dc7ce9b732a1b72102>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type IssueTimelineIssueFragment$data = {
  readonly id: string;
  readonly repository: {
    readonly id: string;
    readonly nameWithOwner: string;
  };
  readonly url: string;
  readonly " $fragmentSpreads": FragmentRefs<"useTimelineItemsBackFragment" | "useTimelineItemsFrontFragment">;
  readonly " $fragmentType": "IssueTimelineIssueFragment";
};
export type IssueTimelineIssueFragment$key = {
  readonly " $data"?: IssueTimelineIssueFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IssueTimelineIssueFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "IssueTimelineIssueFragment",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Repository",
      "kind": "LinkedField",
      "name": "repository",
      "plural": false,
      "selections": [
        (v0/*: any*/),
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "nameWithOwner",
          "storageKey": null
        }
      ],
      "storageKey": null
    },
    {
      "args": [
        {
          "kind": "Literal",
          "name": "count",
          "value": 15
        }
      ],
      "kind": "FragmentSpread",
      "name": "useTimelineItemsFrontFragment"
    },
    {
      "args": [
        {
          "kind": "Literal",
          "name": "count",
          "value": 0
        }
      ],
      "kind": "FragmentSpread",
      "name": "useTimelineItemsBackFragment"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "77f8b22f02292802847ea7519795b347";

export default node;
