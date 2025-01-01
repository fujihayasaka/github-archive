/**
 * @generated SignedSource<<d94bbd328eb52b2007517735815dc8b5>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderFragment } from 'relay-runtime';
export type IssueFieldDataType = "SINGLE_SELECT" | "TEXT" | "%future added value";
export type IssueFieldSingleSelectOptionColor = "BLUE" | "GRAY" | "GREEN" | "ORANGE" | "PINK" | "PURPLE" | "RED" | "YELLOW" | "%future added value";
import type { FragmentRefs } from "relay-runtime";
export type FieldsSectionFieldValues$data = {
  readonly id: string;
  readonly issueFieldValues: {
    readonly nodes: ReadonlyArray<{
      readonly color?: IssueFieldSingleSelectOptionColor;
      readonly description?: string | null | undefined;
      readonly field?: {
        readonly dataType?: IssueFieldDataType;
        readonly id?: string;
        readonly name?: string;
      };
      readonly name?: string;
      readonly value?: string;
    } | null | undefined> | null | undefined;
  };
  readonly " $fragmentType": "FieldsSectionFieldValues";
};
export type FieldsSectionFieldValues$key = {
  readonly " $data"?: FieldsSectionFieldValues$data;
  readonly " $fragmentSpreads": FragmentRefs<"FieldsSectionFieldValues">;
};

const node: ReaderFragment = (function(){
var v0 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "id",
  "storageKey": null
},
v1 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "name",
  "storageKey": null
},
v2 = {
  "alias": null,
  "args": null,
  "kind": "ScalarField",
  "name": "dataType",
  "storageKey": null
};
return {
  "argumentDefinitions": [],
  "kind": "Fragment",
  "metadata": null,
  "name": "FieldsSectionFieldValues",
  "selections": [
    (v0/*: any*/),
    {
      "alias": null,
      "args": [
        {
          "kind": "Literal",
          "name": "first",
          "value": 25
        }
      ],
      "concreteType": "IssueFieldValueConnection",
      "kind": "LinkedField",
      "name": "issueFieldValues",
      "plural": false,
      "selections": [
        {
          "alias": null,
          "args": null,
          "concreteType": null,
          "kind": "LinkedField",
          "name": "nodes",
          "plural": true,
          "selections": [
            {
              "kind": "InlineFragment",
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v0/*: any*/),
                        (v1/*: any*/),
                        (v2/*: any*/)
                      ],
                      "type": "IssueFieldText",
                      "abstractKey": null
                    }
                  ],
                  "storageKey": null
                },
                {
                  "alias": null,
                  "args": null,
                  "kind": "ScalarField",
                  "name": "value",
                  "storageKey": null
                }
              ],
              "type": "IssueFieldTextValue",
              "abstractKey": null
            },
            {
              "kind": "InlineFragment",
              "selections": [
                {
                  "alias": null,
                  "args": null,
                  "concreteType": null,
                  "kind": "LinkedField",
                  "name": "field",
                  "plural": false,
                  "selections": [
                    {
                      "kind": "InlineFragment",
                      "selections": [
                        (v1/*: any*/),
                        (v2/*: any*/)
                      ],
                      "type": "IssueFieldSingleSelect",
                      "abstractKey": null
                    }
                  ],
                  "storageKey": null
                },
                (v1/*: any*/),
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
                }
              ],
              "type": "IssueFieldSingleSelectValue",
              "abstractKey": null
            }
          ],
          "storageKey": null
        }
      ],
      "storageKey": "issueFieldValues(first:25)"
    }
  ],
  "type": "Issue",
  "abstractKey": null
};
})();

(node as any).hash = "18f340a21c24523b1b7d55ea77d453c9";

export default node;
