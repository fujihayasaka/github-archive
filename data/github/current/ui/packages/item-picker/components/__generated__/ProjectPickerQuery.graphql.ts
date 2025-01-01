/**
 * @generated SignedSource<<1f4bc30ad846ebf69fa33c9fddc52d15>>
 * @relayHash 65d0c4f8e3a1c1c9cfd78e5b426cbe49
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 65d0c4f8e3a1c1c9cfd78e5b426cbe49

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type ProjectPickerQuery$variables = {
  owner: string;
  query?: string | null | undefined;
  repo: string;
};
export type ProjectPickerQuery$data = {
  readonly repository: {
    readonly owner: {
      readonly projectsV2?: {
        readonly edges: ReadonlyArray<{
          readonly node: {
            readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
          } | null | undefined;
        } | null | undefined> | null | undefined;
      };
      readonly recentProjects?: {
        readonly edges: ReadonlyArray<{
          readonly node: {
            readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
          } | null | undefined;
        } | null | undefined> | null | undefined;
      };
    };
    readonly projectsV2: {
      readonly nodes: ReadonlyArray<{
        readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
      } | null | undefined> | null | undefined;
    };
    readonly recentProjects: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly " $fragmentSpreads": FragmentRefs<"ProjectPickerProject">;
        } | null | undefined;
      } | null | undefined> | null | undefined;
    };
  } | null | undefined;
};
export type ProjectPickerQuery = {
  response: ProjectPickerQuery$data;
  variables: ProjectPickerQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "owner"
},
v1 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "query"
},
v2 = {
  "defaultValue": null,
  "kind": "LocalArgument",
  "name": "repo"
},
v3 = [
  {
    "kind": "Variable",
    "name": "name",
    "variableName": "repo"
  },
  {
    "kind": "Variable",
    "name": "owner",
    "variableName": "owner"
  }
],
v4 = {
  "kind": "Literal",
  "name": "first",
  "value": 5
},
v5 = [
  (v4/*: any*/),
  {
    "kind": "Literal",
    "name": "orderBy",
    "value": {
      "direction": "DESC",
      "field": "RELEVANCE"
    }
  },
  {
    "kind": "Variable",
    "name": "query",
    "variableName": "query"
  },
  {
    "kind": "Literal",
    "name": "useFullTermQuery",
    "value": true
  }
],
v6 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v7 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "__typename",
  "storageKey": null
},
v8 = [
  (v6/*: any*/),
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
    "name": "closed",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "number",
    "storageKey": null
  },
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
    "kind": "ScalarField",
    "name": "viewerCanUpdate",
    "storageKey": null
  },
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "hasReachedItemsLimit",
    "storageKey": null
  },
  (v7/*: any*/)
],
v9 = [
  {
    "kind": "InlineDataFragmentSpread",
    "name": "ProjectPickerProject",
    "selections": (v8/*: any*/),
    "args": null,
    "argumentDefinitions": ([]/*: any*/)
  }
],
v10 = [
  (v4/*: any*/)
],
v11 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "ProjectV2Edge",
    "kind": "LinkedField",
    "name": "edges",
    "plural": true,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "ProjectV2",
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v9/*: any*/),
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v12 = {
  "alias": null,
  "args": (v10/*: any*/),
  "concreteType": "ProjectV2Connection",
  "kind": "LinkedField",
  "name": "recentProjects",
  "plural": false,
  "selections": (v11/*: any*/),
  "storageKey": "recentProjects(first:5)"
},
v13 = [
  {
    "alias": null,
    "args": (v5/*: any*/),
    "concreteType": "ProjectV2Connection",
    "kind": "LinkedField",
    "name": "projectsV2",
    "plural": false,
    "selections": (v11/*: any*/),
    "storageKey": null
  },
  (v12/*: any*/)
],
v14 = [
  {
    "alias": null,
    "args": null,
    "concreteType": "ProjectV2Edge",
    "kind": "LinkedField",
    "name": "edges",
    "plural": true,
    "selections": [
      {
        "alias": null,
        "args": null,
        "concreteType": "ProjectV2",
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": (v8/*: any*/),
        "storageKey": null
      }
    ],
    "storageKey": null
  }
],
v15 = {
  "alias": null,
  "args": (v10/*: any*/),
  "concreteType": "ProjectV2Connection",
  "kind": "LinkedField",
  "name": "recentProjects",
  "plural": false,
  "selections": (v14/*: any*/),
  "storageKey": "recentProjects(first:5)"
},
v16 = [
  {
    "alias": null,
    "args": (v5/*: any*/),
    "concreteType": "ProjectV2Connection",
    "kind": "LinkedField",
    "name": "projectsV2",
    "plural": false,
    "selections": (v14/*: any*/),
    "storageKey": null
  },
  (v15/*: any*/)
];
return {
  "fragment": {
    "argumentDefinitions": [
      (v0/*: any*/),
      (v1/*: any*/),
      (v2/*: any*/)
    ],
    "kind": "Fragment",
    "metadata": null,
    "name": "ProjectPickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v5/*: any*/),
            "concreteType": "ProjectV2Connection",
            "kind": "LinkedField",
            "name": "projectsV2",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "ProjectV2",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": (v9/*: any*/),
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v12/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "owner",
            "plural": false,
            "selections": [
              {
                "kind": "InlineFragment",
                "selections": (v13/*: any*/),
                "type": "Organization",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v13/*: any*/),
                "type": "User",
                "abstractKey": null
              }
            ],
            "storageKey": null
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
    "argumentDefinitions": [
      (v0/*: any*/),
      (v2/*: any*/),
      (v1/*: any*/)
    ],
    "kind": "Operation",
    "name": "ProjectPickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v3/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": (v5/*: any*/),
            "concreteType": "ProjectV2Connection",
            "kind": "LinkedField",
            "name": "projectsV2",
            "plural": false,
            "selections": [
              {
                "alias": null,
                "args": null,
                "concreteType": "ProjectV2",
                "kind": "LinkedField",
                "name": "nodes",
                "plural": true,
                "selections": (v8/*: any*/),
                "storageKey": null
              }
            ],
            "storageKey": null
          },
          (v15/*: any*/),
          {
            "alias": null,
            "args": null,
            "concreteType": null,
            "kind": "LinkedField",
            "name": "owner",
            "plural": false,
            "selections": [
              (v7/*: any*/),
              {
                "kind": "InlineFragment",
                "selections": (v16/*: any*/),
                "type": "Organization",
                "abstractKey": null
              },
              {
                "kind": "InlineFragment",
                "selections": (v16/*: any*/),
                "type": "User",
                "abstractKey": null
              },
              (v6/*: any*/)
            ],
            "storageKey": null
          },
          (v6/*: any*/)
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "65d0c4f8e3a1c1c9cfd78e5b426cbe49",
    "metadata": {},
    "name": "ProjectPickerQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "6e51c93b49adb71d6853eb253aa6a90d";

export default node;
