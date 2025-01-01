/**
 * @generated SignedSource<<ffb9882f10d27e666e6262a30fd8b69d>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
export type CheckRunState = "ACTION_REQUIRED" | "CANCELLED" | "COMPLETED" | "FAILURE" | "IN_PROGRESS" | "NEUTRAL" | "PENDING" | "QUEUED" | "SKIPPED" | "STALE" | "STARTUP_FAILURE" | "SUCCESS" | "TIMED_OUT" | "WAITING" | "%future added value";
export type StatusState = "ERROR" | "EXPECTED" | "FAILURE" | "PENDING" | "SUCCESS" | "%future added value";
import { FragmentRefs } from "relay-runtime";
export type CheckRunStatus$data = {
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
  readonly " $fragmentType": "CheckRunStatus";
};
export type CheckRunStatus$key = {
  readonly " $data"?: CheckRunStatus$data;
  readonly " $fragmentSpreads": FragmentRefs<"CheckRunStatus">;
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
  "name": "CheckRunStatus",
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
  "type": "Commit",
  "abstractKey": null
};
})();

(node as any).hash = "6dc5ad338ebeeb78e4452c83673b4bec";

export default node;
