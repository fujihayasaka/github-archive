/**
 * @generated SignedSource<<738ca370b3abad069774f2486be83fa1>>
 * @relayHash 7adec652ef8f517f484da9e58d7a0b8b
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

// @relayRequestID 7adec652ef8f517f484da9e58d7a0b8b

import { ConcreteRequest } from 'relay-runtime';
export type FirstTimeContributionBannerContributingGuidelinesQuery$variables = {
  node: string;
};
export type FirstTimeContributionBannerContributingGuidelinesQuery$data = {
  readonly node: {
    readonly contributingGuidelines?: {
      readonly firstTimeContributionLink: string | null | undefined;
    } | null | undefined;
  } | null | undefined;
};
export type FirstTimeContributionBannerContributingGuidelinesQuery = {
  response: FirstTimeContributionBannerContributingGuidelinesQuery$data;
  variables: FirstTimeContributionBannerContributingGuidelinesQuery$variables;
};

const node: ConcreteRequest = (function(){
var v0 = [
  {
    "defaultValue": null,
    "kind": "LocalArgument",
    "name": "node"
  }
],
v1 = [
  {
    "kind": "Variable",
    "name": "id",
    "variableName": "node"
  }
],
v2 = {
  "kind": "InlineFragment",
  "selections": [
    {
      "alias": null,
      "args": null,
      "concreteType": "ContributingGuidelines",
      "kind": "LinkedField",
      "name": "contributingGuidelines",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "kind": "ScalarField",
          "name": "firstTimeContributionLink",
          "storageKey": null
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Repository",
  "abstractKey": null
};
return {
  "fragment": {
    "argumentDefinitions": (v0/*: any*/),
    "kind": "Fragment",
    "metadata": null,
    "name": "FirstTimeContributionBannerContributingGuidelinesQuery",
    "selections": [
      {
        "alias": null,
        "args": (v1/*: any*/),
        "concreteType": null,
        "kind": "LinkedField",
        "name": "node",
        "plural": false,
        "selections": [
          (v2/*: any*/)
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
    "name": "FirstTimeContributionBannerContributingGuidelinesQuery",
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
            "alias": null,
            "args": null,
            "kind": "ScalarField",
            "name": "__typename",
            "storageKey": null
          },
          (v2/*: any*/),
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
    "id": "7adec652ef8f517f484da9e58d7a0b8b",
    "metadata": {},
    "name": "FirstTimeContributionBannerContributingGuidelinesQuery",
    "operationKind": "query",
    "text": null
  }
};
})();

(node as any).hash = "a3f69364d9a035e3974c1bbe5362d35c";

export default node;
