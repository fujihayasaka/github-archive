/**
 * @generated SignedSource<<b0a57a5344c6021f4f1ce7dc8f1cb737>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
export type AssigneesSectionLazyFragment$data = {
  readonly participants: {
    readonly nodes: ReadonlyArray<{
      readonly " $fragmentSpreads": FragmentRefs<"AssigneePickerAssignee">;
    } | null | undefined> | null | undefined;
  };
  readonly repository: {
    readonly installedAppInstallations: {
      readonly edges: ReadonlyArray<{
        readonly node: {
          readonly app: {
            readonly id: string;
            readonly name: string;
            readonly slug: string;
          };
        } | null | undefined;
      } | null | undefined> | null | undefined;
    };
  };
  readonly " $fragmentType": "AssigneesSectionLazyFragment";
};
export type AssigneesSectionLazyFragment$key = {
  readonly " $data"?: AssigneesSectionLazyFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"AssigneesSectionLazyFragment">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "kind": "Literal",
  "name": "first",
  "value": 10
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "AssigneesSectionLazyFragment",
  "selections": [
    {
      "alias": null,
      "args": [
        (v0/*: any*/)
      ],
      "concreteType": "UserConnection",
      "kind": "LinkedField",
      "name": "participants",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": "User",
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            {
              "kind": "InlineDataFragmentSpread",
              "name": "AssigneePickerAssignee",
              "selections": [
                (v1/*: any*/),
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "login",
                  "storageKey": null
                },
                (v2/*: any*/),
                {
                  "alias": null,
                  "args": [
                    {
                      "kind": "Literal",
                      "name": "size",
                      "value": 64
                    }
                  ],
                  "kind": "ScalarField",
                  "name": "avatarUrl",
                  "storageKey": "avatarUrl(size:64)"
                }
              ],
              "args": null,
              "argumentDefinitions": []
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "participants(first:10)"
    },
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
          "args": [
            (v0/*: any*/),
            {
              "kind": "Literal",
              "name": "isAssignable",
              "value": true
            }
          ],
          "concreteType": "InstalledAppInstallationsConnection",
          "kind": "LinkedField",
          "name": "installedAppInstallations",
          "plural": false,
          "selections": [
            {
              "alias": null,
              "args": null,
              "concreteType": "IntegrationInstallationEdge",
              "kind": "LinkedField",
              "name": "edges",
              "plural": true,
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": "IntegrationInstallation",
                  "kind": "LinkedField",
                  "name": "node",
                  "plural": false,
                  "selections": [
                    {
                      "alias": null,
                      "args": null,
                      "concreteType": "App",
                      "kind": "LinkedField",
                      "name": "app",
                      "plural": false,
                      "selections": [
                        (v1/*: any*/),
                        {
                          "alias": null,
                          "args": null,
                          "kind": "ScalarField",
                          "name": "slug",
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
              "storageKey": null
            }
          ],
          "storageKey": "installedAppInstallations(first:10,isAssignable:true)"
        }
      ],
      "storageKey": null
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "9f385626a6068246e390f3b508c2b91f";

export default node;
