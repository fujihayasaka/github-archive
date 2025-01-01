import {RuleTester} from '@typescript-eslint/rule-tester'
import {AST_NODE_TYPES} from '@typescript-eslint/utils'
import rule from '../migrated-package-imports'
import path from 'node:path'

const rootDir = path.resolve(__dirname, '../../../../../')

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('migrated-package-imports', rule as any, {
  valid: [
    {
      code: `
        import {foo} from '@github-ui/example-package'
      `,
      filename: path.join(rootDir, 'app/assets/modules/foo/bar.ts'),
    },
  ],

  invalid: [
    {
      code: `
        import {foo} from '../example-file'
      `,
      output: `
        import {foo} from '@github-ui/example-package'
      `,
      filename: path.join(rootDir, 'app/assets/modules/foo/bar.ts'),
      errors: [
        {
          messageId: 'migratedPackageImport',
          type: AST_NODE_TYPES.Literal,
        },
      ],
    },
  ],
})
