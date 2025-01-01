/**
 * @generated SignedSource<<6d42ca70706194aebfc9849b4d9f82b0>>
 * @lightSyntaxTransform
 * @nogrep
 */

/* tslint:disable */
/* eslint-disable */
// @ts-nocheck

import type { ReaderInlineDataFragment } from 'relay-runtime';
import type { FragmentRefs } from "relay-runtime";
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
