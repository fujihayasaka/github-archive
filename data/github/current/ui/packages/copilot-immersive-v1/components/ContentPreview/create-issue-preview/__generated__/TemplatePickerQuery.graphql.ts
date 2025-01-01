/**
 * @generated SignedSource<<3ba9f9396a7b943c6946528ba3fc09a8>>
 * @relayHash 453f03781d915408c3c338e5d346e0be
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 453f03781d915408c3c338e5d346e0be

import type { ConcreteRequest } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TemplatePickerQuery$variables = {
  owner: string;
  repo: string;
};
export type TemplatePickerQuery$data = {
  readonly repository: {
    readonly issueForms: ReadonlyArray<{
      readonly __typename: "IssueForm";
      readonly " $fragmentSpreads": FragmentRefs<"TemplatePickerForm">;
    }> | null | undefined;
    readonly issueTemplates: ReadonlyArray<{
      readonly __typename: "IssueTemplate";
      readonly " $fragmentSpreads": FragmentRefs<"TemplatePickerTemplate">;
    }> | null | undefined;
  } | null | undefined;
};
export type TemplatePickerQuery = {
  response: TemplatePickerQuery$data;
  variables: TemplatePickerQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "owner"
  },
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "repo"
  }
],
v1 = [
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
  "name": "filename",
  "storageKey": null
},
v4 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v5 = [
  (v2/*: any*/),
  (v3/*: any*/),
  (v4/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "description",
    "storageKey": null
  }
],
v6 = [
  (v2/*: any*/),
  (v3/*: any*/),
  (v4/*: any*/),
  {
    "alias": null,
    "args": null,
    "kind": "ScalarField",
    "name": "about",
    "storageKey": null
  }
];
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "TemplatePickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueForm",
            "kind": "LinkedField",
            "name": "issueForms",
            "plural": true,
            "selections": [
              (v2/*: any*/),
              {
                "kind": "InlineDataFragmentSpread",
                "name": "TemplatePickerForm",
                "selections": (v5/*: any*/),
                "args": null,
                "argumentDefinitions": []
              }
            ],
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueTemplate",
            "kind": "LinkedField",
            "name": "issueTemplates",
            "plural": true,
            "selections": [
              (v2/*: any*/),
              {
                "kind": "InlineDataFragmentSpread",
                "name": "TemplatePickerTemplate",
                "selections": (v6/*: any*/),
                "args": null,
                "argumentDefinitions": []
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
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Operation",
    "name": "TemplatePickerQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": "Repository",
        "kind": "LinkedField",
        "name": "repository",
        "plural": false,
        "selections": [
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueForm",
            "kind": "LinkedField",
            "name": "issueForms",
            "plural": true,
            "selections": (v5/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "concreteType": "IssueTemplate",
            "kind": "LinkedField",
            "name": "issueTemplates",
            "plural": true,
            "selections": (v6/*: any*/),
            "storageKey": null
          },
          {
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "id",
            "storageKey": null
          }
        ],
        "storageKey": null
      }
    ]
  },
  "params": {
    "id": "453f03781d915408c3c338e5d346e0be",
    "metadata": {},
    "name": "TemplatePickerQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "582a468668cd62a5a95ad0f91f7ea5e5";

export default node;
