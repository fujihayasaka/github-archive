/**
 * @generated SignedSource<<4a727c5b130de1c248ec8cb3604341da>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ActivityView_PullRequestTimeline_pullRequest$data = {
  readonly author: {
    readonly login: string;
  } | null | undefined;
  readonly id: string;
  readonly repository: {
    readonly id: string;
    readonly url: string;
  };
  readonly url: string;
  readonly viewerCanComment: boolean;
  readonly " $fragmentType": "ActivityView_PullRequestTimeline_pullRequest";
};
export type ActivityView_PullRequestTimeline_pullRequest$key = {
  readonly " $data"?: ActivityView_PullRequestTimeline_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"ActivityView_PullRequestTimeline_pullRequest">;
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
  "name": "url",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "ActivityView_PullRequestTimeline_pullRequest",
  "selections": [
    (v0/*: any*/),
    (v1/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanComment",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": null,
      "kind": "LinkedField",
      "name": "author",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "login",
          "storageKey": null
        }
      ],
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
        (v1/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};
})();

(node as any).hash = "984e300264d936a422ab9d04bc516f56";

export default node;
