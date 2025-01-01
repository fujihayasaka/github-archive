/**
 * @generated SignedSource<<0c513c244c28e89852508430a81ff75e>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type CheckRunState = "ACTION_REQUIRED" | "CANCELLED" | "COMPLETED" | "FAILURE" | "IN_PROGRESS" | "NEUTRAL" | "PENDING" | "QUEUED" | "SKIPPED" | "STALE" | "STARTUP_FAILURE" | "SUCCESS" | "TIMED_OUT" | "WAITING" | "%future added value";
export type StatusState = "ERROR" | "EXPECTED" | "FAILURE" | "PENDING" | "SUCCESS" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type CheckRunStatusFromPullRequest$data = {
  readonly statusCheckRollup: {
    readonly contexts: {
      readonly checkRunCount: number;
      readonly checkRunCountsByState: ReadonlyArray<{
        readonly count: number;
        readonly state: CheckRunState;
      }> | null | undefined;
    };
    readonly state: StatusState;
  } | null | undefined;
  readonly " $fragmentType": "CheckRunStatusFromPullRequest";
};
export type CheckRunStatusFromPullRequest$key = {
  readonly " $data"?: CheckRunStatusFromPullRequest$data;
  readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatusFromPullRequest">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "state",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "CheckRunStatusFromPullRequest",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "StatusCheckRollup",
      "kind": "LinkedField",
      "name": "statusCheckRollup",
      "plural": false,
      "selections": [
        (v0/*: any*/),
        {
          "alias": null,
          "args": null,
          "concreteType": "StatusCheckRollupContextConnection",
          "kind": "LinkedField",
          "name": "contexts",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "kind": "ScalarField",
              "name": "checkRunCount",
              "storageKey": null
            },
            {
              "alias": null,
              "args": null,
              "concreteType": "CheckRunStateCount",
              "kind": "LinkedField",
              "name": "checkRunCountsByState",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "count",
                  "storageKey": null
                },
                (v0/*: any*/)
              ],
              "storageKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "PullRequest",
  "abstractKey": null
};
})();

(node as any).hash = "d75a7a69f99bfff558b671bcd7aeb083";

export default node;
