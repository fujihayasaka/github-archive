/**
 * @generated SignedSource<<02e897ba5193dd903bdb7819781ea8d2>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type TypesSectionFragment$data = {
  readonly id: string;
  readonly repository: {
    readonly issueTypes: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly id: string;
        } | null | undefined;
      } | null | undefined> | null | undefined;
    } | null | undefined;
    readonly name: string;
    readonly nameWithOwner: string;
    readonly owner: {
      readonly login: string;
    };
  };
  readonly viewerCanType: boolean | null | undefined;
  readonly " $fragmentSpreads": FragmentRefs<"TypesSectionTypeFragment">;
  readonly " $fragmentType": "TypesSectionFragment";
};
export type TypesSectionFragment$key = {
  readonly " $data"?: TypesSectionFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"TypesSectionFragment">;
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
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "TypesSectionFragment",
  "selections": [
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
          "kind": "ScalarField",
          "name": "nameWithOwner",
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
          "args": [
            {
              "kind": "Literal",
              "name": "first",
              "value": 10
            }
          ],
          "concreteType": "IssueTypeConnection",
          "kind": "LinkedField",
          "name": "issueTypes",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "IssueTypeEdge",
              "kind": "LinkedField",
              "name": "edges",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "IssueType",
                  "kind": "LinkedField",
                  "name": "node",
                  "plural": false,
                  "selections": [
                    (v0/*: any*/)
                  ],
                  "storageKey": null
                }
              ],
              "storageKey": null
            }
          ],
          "storageKey": "issueTypes(first:10)"
        }
      ],
      "storageKey": null
    },
    (v0/*: any*/),
    {
      "args": null,
      "kind": "FragmentSpread",
      "name": "TypesSectionTypeFragment"
    },
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "viewerCanType",
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "0ff8c6dca741e190d4b8ec1c12fee9f1";

export default node;
