/**
 * @generated SignedSource<<31f6309e735db5f921455da97e593017>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type TeamCheckboxItem$data = {
  readonly avatarUrl: string | null | undefined;
  readonly id: string;
  readonly name: string;
  readonly organization: {
    readonly name: string | null | undefined;
  };
  readonly " $fragmentType": "TeamCheckboxItem";
};
export type TeamCheckboxItem$key = {
  readonly " $data"?: TeamCheckboxItem$data;
  readonly " $fragmentSpreads": FragmentRefs<"TeamCheckboxItem">;
};

const node: ReaderFragment = (function(){
var v0 = {
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
  "name": "TeamCheckboxItem",
  "selections": [
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "id",
      "storageKey": null
    },
    (v0/*: any*/),
    {
      "alias": null,
      "args": null,
      "kind": "ScalarField",
      "name": "avatarUrl",
      "storageKey": null
    },
    {
      "alias": null,
      "args": null,
      "concreteType": "Organization",
      "kind": "LinkedField",
      "name": "organization",
      "plural": false,
      "selections": [
        (v0/*: any*/)
      ],
      "storageKey": null
    }
  ],
  "type": "Team",
  "abstractKey": null
};
})();

(node as any).hash = "27ef2c00286726a048ff758bf090587a";

export default node;
