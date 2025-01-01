/**
 * @generated SignedSource<<969e6a11016755d88cb2eff5e4707ae0>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestItem$data = {
  readonly __typename: "PullRequest";
  readonly id: string;
  readonly repository: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly title: string;
  readonly titleHTML: string;
  readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatusFromPullRequest" | "IssuePullRequestDescription" | "IssuePullRequestStateIcon" | "IssuePullRequestTitle" | "PullRequestItemHeadCommit">;
  readonly " $fragmentType": "PullRequestItem";
};
export type PullRequestItem$key = {
  readonly " $data"?: PullRequestItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestItem">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "kind": "Variable",
  "name": "includeGitData",
  "variableName": "includeGitData"
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "includeGitData"
    },
    {
      "defaultValue": true,
      "kind": "LocalArgument",
      "name": "includeMilestone"
    },
    {
      "defaultValue": 10,
      "kind": "LocalArgument",
      "name": "labelPageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "PullRequestItem",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    },
    {
      "condition": "includeGitData",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "PullRequestItemHeadCommit"
        },
        {
          "args": null,
          "kind": "FragmentSpread",
          "name": "CheckRunStatusFromPullRequest"
        }
      ]
    },
    {
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
          "name": "name",
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "owner",
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
        }
      ],
      "storageKey": null
    },
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
      "name": "titleHTML",
      "storageKey": null
    },
    {
      "args": [
        {
          "kind": "Variable",
          "name": "labelPageSize",
          "variableName": "labelPageSize"
        }
      ],
      "kind": "FragmentSpread",
      "name": "IssuePullRequestTitle"
    },
    {
      "args": [
        (v0/*: any*/),
        {
          "kind": "Variable",
          "name": "includeMilestone",
          "variableName": "includeMilestone"
        }
      ],
      "kind": "FragmentSpread",
      "name": "IssuePullRequestDescription"
    },
    {
      "args": [
        (v0/*: any*/)
      ],
      "kind": "FragmentSpread",
      "name": "IssuePullRequestStateIcon"
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};
})();

(node as any).hash = "6141a029801edc1d0f101b336064cb62";

export default node;
