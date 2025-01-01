/**
 * @generated SignedSource<<2371946009f9db53b0fed2441b86cfcc>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type ProjectsSectionFragment$data = {
  readonly id?: string;
  readonly number?: number;
  readonly projectItemsNext?: {
    readonly edges: ReadonlyArray<{
      readonly node: {
        readonly id: string;
        readonly project: {
          readonly closed: boolean;
          readonly id: string;
          readonly title: string;
          readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
        };
        readonly " $fragmentSpreads": FragmentRefs<"ProjectItemSection">;
      } | null | undefined;
    } | null | undefined> | null | undefined;
  } | null | undefined;
  readonly repository?: {
    readonly isArchived: boolean;
    readonly name: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly viewerCanUpdate?: boolean;
  readonly viewerCanUpdateMetadata?: boolean | null | undefined;
  readonly " $fragmentType": "ProjectsSectionFragment";
};
export type ProjectsSectionFragment$key = {
  readonly " $data"?: ProjectsSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"ProjectsSectionFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "count": null,
  "cursor": null,
  "direction": "forward",
  "path": [
    "projectItemsNext"
  ]
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "number",
  "storageKey": null
},
v2 = {
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
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "isArchived",
      "storageKey": null
    }
  ],
  "storageKey": null
},
v3 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v4 = [
  {
    "kind": "Variable",
    "name": "allowedOwner",
    "variableName": "allowedOwner"
  }
],
v5 = {
  "args": null,
  "kind": "FragmentSpread",
  "name": "ProjectItemSection"
},
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "title",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "closed",
  "storageKey": null
},
v8 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "viewerCanUpdate",
  "storageKey": null
},
v9 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v10 = {
  "kind": "InlineDataFragmentSpread",
  "name": "ProjectPickerProject",
  "selections": [
    (v3/*: any*/),
    (v6/*: any*/),
    (v7/*: any*/),
    (v1/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "url",
      "storageKey": null
    },
    (v8/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasReachedItemsLimit",
      "storageKey": null
    },
    (v9/*: any*/)
  ],
  "args": null,
  "argumentDefinitions": ([]/*: any*/)
},
v11 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "cursor",
  "storageKey": null
},
v12 = {
  "alias": null,
  "args": null,
  "concreteType": "PageInfo",
  "kind": "LinkedField",
  "name": "pageInfo",
  "plural": false,
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "endCursor",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "hasNextPage",
      "storageKey": null
    }
  ],
  "storageKey": null
};
return {
  "argumentDefinitions": [
    {
      "defaultValue": null,
      "kind": "LocalArgument",
      "name": "allowedOwner"
    }
  ],
  "kind": "Fragment",
  "metadata": {
    "connection": [
      (v0/*: any*/),
      (v0/*: any*/)
    ]
  },
  "name": "ProjectsSectionFragment",
  "selections": [
    {
      "kind": "InlineFragment",
      "selections": [
        (v1/*: any*/),
        (v2/*: any*/),
        (v3/*: any*/),
        {
          "alias": "projectItemsNext",
          "args": (v4/*: any*/),
          "concreteType": "ProjectV2ItemConnection",
          "kind": "LinkedField",
          "name": "__ProjectSection_projectItemsNext_connection",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2ItemEdge",
              "kind": "LinkedField",
              "name": "edges",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "ProjectV2Item",
                  "kind": "LinkedField",
                  "name": "node",
                  "plural": false,
                  "selections": [
                    (v3/*: any*/),
                    (v5/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "ProjectV2",
                      "kind": "LinkedField",
                      "name": "project",
                      "plural": false,
                      "selections": [
                        (v10/*: any*/),
                        (v7/*: any*/),
                        (v6/*: any*/),
                        (v3/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v9/*: any*/)
                  ],
                  "storageKey": null
                },
                (v11/*: any*/)
              ],
              "storageKey": null
            },
            (v12/*: any*/)
          ],
          "storageKey": null
        },
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "viewerCanUpdateMetadata",
          "storageKey": null
        }
      ],
      "type": "Issue",
      "abstractKey": null
    },
    {
      "kind": "InlineFragment",
      "selections": [
        (v1/*: any*/),
        (v2/*: any*/),
        (v3/*: any*/),
        {
          "alias": "projectItemsNext",
          "args": (v4/*: any*/),
          "concreteType": "ProjectV2ItemConnection",
          "kind": "LinkedField",
          "name": "__ProjectSection_projectItemsNext_connection",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "ProjectV2ItemEdge",
              "kind": "LinkedField",
              "name": "edges",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "ProjectV2Item",
                  "kind": "LinkedField",
                  "name": "node",
                  "plural": false,
                  "selections": [
                    (v3/*: any*/),
                    (v5/*: any*/),
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "ProjectV2",
                      "kind": "LinkedField",
                      "name": "project",
                      "plural": false,
                      "selections": [
                        (v7/*: any*/),
                        (v10/*: any*/),
                        (v6/*: any*/),
                        (v3/*: any*/)
                      ],
                      "storageKey": null
                    },
                    (v9/*: any*/)
                  ],
                  "storageKey": null
                },
                (v11/*: any*/)
              ],
              "storageKey": null
            },
            (v12/*: any*/)
          ],
          "storageKey": null
        },
        (v8/*: any*/)
      ],
      "type": "PullRequest",
      "abstractKey": null
    }
  ],
  "type": "IssueOrPullRequest",
  "abstractKey": "__isIssueOrPullRequest"
};
})();

(node as any).hash = "b0be06543ecd1d954094de888faf8ec6";

export default node;
