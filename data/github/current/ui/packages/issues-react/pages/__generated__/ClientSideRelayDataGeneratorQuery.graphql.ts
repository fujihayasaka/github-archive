/**
 * @generated SignedSource<<cf0c86ed93ccb813eb4302a8a5f7eade>>
 * @relayHash d174fccd26c72c8f6cfa7e08b08f1e0f
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID d174fccd26c72c8f6cfa7e08b08f1e0f

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ClientSideRelayDataGeneratorQuery$variables = {
  ids: ReadonlyArray<string>;
};
export type ClientSideRelayDataGeneratorQuery$data = {
  readonly nodes: ReadonlyArray<{
    readonly " $fragmentSpreads": FragmentRefs<"DashboardSearchCurrentViewFragment" | "IssueDashboardCustomViewPageCurrentViewFragment" | "IssueDetailCurrentViewFragment" | "ListCurrentViewFragment" | "ViewOptionsButtonCurrentViewFragment">;
  } | null | undefined>;
};
export type ClientSideRelayDataGeneratorQuery = {
  response: ClientSideRelayDataGeneratorQuery$data;
  variables: ClientSideRelayDataGeneratorQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "ids"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "ids",
    "variableName": "ids"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "ClientSideRelayDataGeneratorQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          {
            "kind": "InlineFragment",
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "ListCurrentViewFragment"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueDetailCurrentViewFragment"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "ViewOptionsButtonCurrentViewFragment"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "DashboardSearchCurrentViewFragment"
              },
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "IssueDashboardCustomViewPageCurrentViewFragment"
              }
            ],
            "type": "Shortcutable",
            "abstractKey": "__isShortcutable"
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Query",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "ClientSideRelayDataGeneratorQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "nodes",
        "plural": true,
        "selections": [
          (v2/*: any*/),
          (v3/*: any*/),
          {
            "kind": "InlineFragment",
            "selections": [
              (v4/*: any*/),
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "query",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "concreteType": "Repository",
                "kind": "LinkedField",
                "name": "scopingRepository",
                "plural": false,
                "selections": [
                  (v4/*: any*/),
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": null,
                    "kind": "LinkedField",
                    "name": "owner",
                    "plural": false,
                    "selections": [
                      (v2/*: any*/),
                      {
                        "alias": null,
                        "args": null,
                        "kind": "ScalarField",
                        "name": "login",
                        "storageKey": null
                      },
                      (v3/*: any*/)
                    ],
                    "storageKey": null
                  },
                  (v3/*: any*/)
                ],
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "description",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "icon",
                "storageKey": null
              },
              {
                "alias": null,
                "args": null,
                "kind": "ScalarField",
                "name": "color",
                "storageKey": null
              }
            ],
            "type": "Shortcutable",
            "abstractKey": "__isShortcutable"
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "d174fccd26c72c8f6cfa7e08b08f1e0f",
    "metadata": {},
    "name": "ClientSideRelayDataGeneratorQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "6e8de1e443c2c18d9ec8c0ab909308fe";

export default node;
