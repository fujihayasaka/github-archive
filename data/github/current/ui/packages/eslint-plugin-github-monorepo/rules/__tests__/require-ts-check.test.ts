import {RuleTester} from 'eslint'
import rule from '../require-ts-check'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

ruleTester.run('require-ts-check', rule, {
  valid: [
    {
      code: `// @ts-check\nconst x = 1;`,
      filename: 'test.js',
    },
    {
      code: `// @ts-check\nfunction f() {}`,
      filename: 'file.mjs',
    },
    {
      code: `// @ts-check\nimport React from 'react';`,
      filename: 'component.jsx',
    },
    {
      code: `// @ts-check\nmodule.exports = {};`,
      filename: 'config.cjs',
    },
    {
      code: `const x = 1;`, // Not a JS file → should not trigger rule
      filename: 'index.ts',
    },
  ],

  invalid: [
    {
      code: `const x = 1;`,
      filename: 'no-check.js',
      errors: [{messageId: 'missingTsCheck'}],
      output: `// @ts-check\nconst x = 1;`,
    },
    {
      code: `/* some comment */\nconst x = 2;`,
      filename: 'file.jsx',
      errors: [{messageId: 'missingTsCheck'}],
      output: `// @ts-check\n/* some comment */\nconst x = 2;`,
    },
    {
      code: `\n\nconsole.log('test');`,
      filename: 'file.cjs',
      errors: [{messageId: 'missingTsCheck'}],
      output: `// @ts-check\n\n\nconsole.log('test');`,
    },
    {
      code: `// other comment\nlet y = 3;`,
      filename: 'file.mjs',
      errors: [{messageId: 'missingTsCheck'}],
      output: `// @ts-check\n// other comment\nlet y = 3;`,
    },
  ],
})
