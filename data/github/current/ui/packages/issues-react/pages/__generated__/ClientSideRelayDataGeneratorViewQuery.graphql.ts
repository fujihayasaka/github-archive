/**
 * @generated SignedSource<<c85b4df3c2cf412df6b9bc083bc9e97a>>
 * @relayHash 7f3619bf561a2557f3f66ac4573a1484
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7f3619bf561a2557f3f66ac4573a1484

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ClientSideRelayDataGeneratorViewQuery$variables = {
  id?: string | null | undefined;
};
export type ClientSideRelayDataGeneratorViewQuery$data = {
  readonly node: {
    readonly " $fragmentSpreads": FragmentRefs<"DashboardSearchCurrentViewFragment" | "IssueDashboardCustomViewPageCurrentViewFragment" | "IssueDetailCurrentViewFragment" | "ListCurrentViewFragment" | "ViewOptionsButtonCurrentViewFragment">;
  } | null | undefined;
};
export type ClientSideRelayDataGeneratorViewQuery = {
  response: ClientSideRelayDataGeneratorViewQuery$data;
  variables: ClientSideRelayDataGeneratorViewQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": "assigned",
    "kind": "LocalArgument",
    "name": "id"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "id"
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
    "name": "ClientSideRelayDataGeneratorViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
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
    "name": "ClientSideRelayDataGeneratorViewQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
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
    "id": "7f3619bf561a2557f3f66ac4573a1484",
    "metadata": {},
    "name": "ClientSideRelayDataGeneratorViewQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "e6f9adaa490e46c90c0c67c9a654141d";

export default node;
