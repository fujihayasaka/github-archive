/**
 * @generated SignedSource<<897c48732a49a170df0d77deea98995f>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import { ReaderInlineDataFragment } from 'relay-runtime';
import { FragmentRefs } from "relay-runtime";
export type IterationFieldIterationFragment$data = {
  readonly duration: number;
  readonly id: string;
  readonly startDate: any;
  readonly title: string;
  readonly titleHTML: string;
  readonly " $fragmentType": "IterationFieldIterationFragment";
};
export type IterationFieldIterationFragment$key = {
  readonly " $data"?: IterationFieldIterationFragment$data;
  readonly " $fragmentSpreads": FragmentRefs<"IterationFieldIterationFragment">;
};

const node: ReaderInlineDataFragment = {
  "kind": "InlineDataFragment",
  "name": "IterationFieldIterationFragment"
};

(node as any).hash = "28591c2749a30e9b111acd7e77a057f9";

export default node;
