/**
 * @generated SignedSource<<fbeab0fbea1b56ef05956771ea15d9b0>>
 * @relayHash 04e470162ffcd70b1897b4670789bad9
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 04e470162ffcd70b1897b4670789bad9

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type SearchShortcutColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "%future added value";
export type SearchShortcutIcon = "ALERT" | "BEAKER" | "BOOKMARK" | "BRIEFCASE" | "BUG" | "CALENDAR" | "CLOCK" | "CODESCAN" | "CODE_REVIEW" | "COMMENT_DISCUSSION" | "DEPENDABOT" | "EYE" | "FILE_DIFF" | "FLAME" | "GIT_PULL_REQUEST" | "HUBOT" | "ISSUE_OPENED" | "MENTION" | "METER" | "MOON" | "NORTH_STAR" | "ORGANIZATION" | "PEOPLE" | "ROCKET" | "SMILEY" | "SQUIRREL" | "SUN" | "TELESCOPE" | "TERMINAL" | "TOOLS" | "ZAP" | "%future added value";
export type RemoveDashboardSearchShortcutInput = {
  clientMutationId?: string | null | undefined;
  shortcutId: string;
};
export type removeUserViewMutation$variables = {
  input: RemoveDashboardSearchShortcutInput;
};
export type removeUserViewMutation$data = {
  readonly removeDashboardSearchShortcut: {
    readonly dashboard: {
      readonly " $fragmentSpreads": FragmentRefs<"SavedViewsShortcutsFragment">;
    } | null | undefined;
    readonly shortcut: {
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type removeUserViewMutation$rawResponse = {
  readonly removeDashboardSearchShortcut: {
    readonly dashboard: {
      readonly id: string;
      readonly shortcuts: {
        readonly nodes: ReadonlyArray<{
          readonly color: SearchShortcutColor;
          readonly description: string;
          readonly icon: SearchShortcutIcon;
          readonly id: string;
          readonly name: string;
          readonly query: string;
          readonly scopingRepository: {
            readonly id: string;
            readonly name: string;
            readonly owner: {
              readonly __typename: string;
              readonly id: string;
              readonly login: string;
            };
          } | null | undefined;
        } | null | undefined> | null | undefined;
        readonly totalCount: number;
      };
    } | null | undefined;
    readonly shortcut: {
      readonly id: string;
    } | null | undefined;
  } | null | undefined;
};
export type removeUserViewMutation = {
  rawResponse: removeUserViewMutation$rawResponse;
  response: removeUserViewMutation$data;
  variables: removeUserViewMutation$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "input"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "input",
    "variableName": "input"
  }
],
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v3 = {
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
    "name": "removeUserViewMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "RemoveDashboardSearchShortcutPayload",
        "kind": "LinkedField",
        "name": "removeDashboardSearchShortcut",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "UserDashboard",
            "kind": "LinkedField",
            "name": "dashboard",
            "plural": false,
            "selections": [
              {
                "args": null,
                "kind": "FragmentSpread",
                "name": "SavedViewsShortcutsFragment"
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "SearchShortcut",
            "kind": "LinkedField",
            "name": "shortcut",
            "plural": false,
            "selections": [
              (v2/*: any*/)
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ],
    "type": "Mutation",
    "abstractKey": null
  },
  "kind": "Request",
  "operation": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "removeUserViewMutation",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "RemoveDashboardSearchShortcutPayload",
        "kind": "LinkedField",
        "name": "removeDashboardSearchShortcut",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "UserDashboard",
            "kind": "LinkedField",
            "name": "dashboard",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": [
                  {
                    "kind": "Literal",
                    "name": "first",
                    "value": 25
                  }
                ],
                "concreteType": "SearchShortcutConnection",
                "kind": "LinkedField",
                "name": "shortcuts",
                "plural": false,
                "selections": [
                  {
                    "alias": null,
                    "args": null,
                    "kind": "ScalarField",
                    "name": "totalCount",
                    "storageKey": null
                  },
                  {
                    "alias": null,
                    "args": null,
                    "concreteType": "SearchShortcut",
                    "kind": "LinkedField",
                    "name": "nodes",
                    "plural": true,
                    "selections": [
                      (v2/*: any*/),
                      (v3/*: any*/),
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
                        "concreteType": "Repository",
                        "kind": "LinkedField",
                        "name": "scopingRepository",
                        "plural": false,
                        "selections": [
                          (v3/*: any*/),
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
                                "name": "__typename",
                                "storageKey": null
                              },
                              {
                                "alias": null,
                                "args": null,
                                "kind": "ScalarField",
                                "name": "login",
                                "storageKey": null
                              },
                              (v2/*: any*/)
                            ],
                            "storageKey": null
                          },
                          (v2/*: any*/)
                        ],
                        "storageKey": null
                      }
                    ],
                    "storageKey": null
                  }
                ],
                "storageKey": "shortcuts(first:25)"
              },
              (v2/*: any*/)
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "SearchShortcut",
            "kind": "LinkedField",
            "name": "shortcut",
            "plural": false,
            "selections": [
              (v2/*: any*/),
              {
                "alias": null,
                "args": null,
                "filters": null,
                "handle": "deleteRecord",
                "key": "",
                "kind": "ScalarHandle",
                "name": "id"
              }
            ],
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "04e470162ffcd70b1897b4670789bad9",
    "metadata": {},
    "name": "removeUserViewMutation",
    "operationKind": "mutation",
    "text": null
  }
};
})();

(node as any).hash = "245da169b3f76a221246bc00c4db41b4";

export default node;
