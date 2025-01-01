import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../prefer-const-object-to-enum'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

ruleTester.run('convert-enum-to-const-object', rule, {
  valid: [
    {
      code: `const myObject = { A: "A", B: "B" } as const;`,
    },
    {
      code: `type MyType = (typeof myObject)[keyof typeof myObject];`,
    },
  ],
  invalid: [
    {
      code: `enum Colors { RED, GREEN, BLUE }`,
      errors: [{messageId: 'discourageEnum', data: {enumName: 'Colors'}}],
      output: `const Colors = {
  RED: "RED",
  GREEN: "GREEN",
  BLUE: "BLUE"
} as const;

type Colors = (typeof Colors)[keyof typeof Colors];`,
    },
    {
      code: `const enum Status { ACTIVE, INACTIVE }`,
      errors: [{messageId: 'discourageConstEnum', data: {enumName: 'Status'}}],
      output: `const Status = {
  ACTIVE: "ACTIVE",
  INACTIVE: "INACTIVE"
} as const;

type Status = (typeof Status)[keyof typeof Status];`,
    },
    {
      code: `export enum Direction { NORTH = "N", SOUTH = "S" }`,
      errors: [{messageId: 'discourageEnum', data: {enumName: 'Direction'}}],
      output: `export const Direction = {
  NORTH: "N",
  SOUTH: "S"
} as const;

export type Direction = (typeof Direction)[keyof typeof Direction];`,
    },
  ],
})
