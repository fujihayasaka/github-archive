/**
 * @generated SignedSource<<2c49f43c5987250b1f584a9fe803f39f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type PullRequestRow_pullRequest$data = {
  readonly __typename: "PullRequest";
  readonly headCommit?: {
    readonly commit: {
      readonly id: string;
    };
  } | null | undefined;
  readonly id: string;
  readonly number: number;
  readonly repository: {
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestItem">;
  readonly " $fragmentType": "PullRequestRow_pullRequest";
};
export type PullRequestRow_pullRequest$key = {
  readonly " $data"?: PullRequestRow_pullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"PullRequestRow_pullRequest">;
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
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "labelPageSize"
    }
  ],
  "kind": "Fragment",
  "metadata": null,
  "name": "PullRequestRow_pullRequest",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "__typename",
      "storageKey": null
    },
    (v0/*: any*/),
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
      "args": [
        {
          "kind": "Variable",
          "name": "includeGitData",
          "variableName": "includeGitData"
        },
        {
          "kind": "Variable",
          "name": "includeMilestone",
          "variableName": "includeMilestone"
        },
        {
          "kind": "Variable",
          "name": "labelPageSize",
          "variableName": "labelPageSize"
        }
      ],
      "kind": "FragmentSpread",
      "name": "PullRequestItem"
    },
    {
      "condition": "includeGitData",
      "kind": "Condition",
      "passingValue": true,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "PullRequestCommit",
          "kind": "LinkedField",
          "name": "headCommit",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "Commit",
              "kind": "LinkedField",
              "name": "commit",
              "plural": false,
              "selections": [
                (v0/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ]
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "number",
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};
})();

(node as any).hash = "341904fa888e7deff66a0c98b01b7491";

export default node;
