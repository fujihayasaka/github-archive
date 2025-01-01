import {RuleTester} from '@typescript-eslint/rule-tester'
import rule from '../package-json-required-scripts'

const ruleTester = new RuleTester({
  languageOptions: {
    parserOptions: {
      ecmaVersion: 2018,
      sourceType: 'module',
    },
  },
})

// eslint-disable-next-line @typescript-eslint/no-explicit-any
ruleTester.run('package-json-required-scripts', rule as any, {
  valid: [
    {
      code: JSON.stringify({
        scripts: {
          lint: 'eslint . --cache',
          stylelint: 'stylelint --aei --rd "**/*.css"',
          test: 'jest',
          tsc: 'tsc',
        },
      }),
      filename: '/path/to/package/package.json',
    },
    {
      code: JSON.stringify({
        scripts: {
          lint: 'eslint . --cache',
          stylelint: 'stylelint --aei --rd "**/*.css"',
          test: 'ui-test',
          tsc: 'tsc',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      }),
      filename: '/path/to/package/package.json',
    },
    {
      code: JSON.stringify({
        scripts: {
          lint: 'eslint . --cache',
          stylelint: 'stylelint --aei --rd "**/*.css"',
          test: 'jest',
          tsc: 'tsc',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      }),
      filename: '/ui/packages/ui-packages-tooling/package.json',
    },
  ],

  invalid: [
    // missing stylelint and tsc scripts
    {
      code: JSON.stringify({
        scripts: {
          lint: 'eslint . --cache',
          test: 'jest',
        },
      }),
      filename: '/path/to/package/package.json',
      errors: [{messageId: 'missingScript', data: {script: 'stylelint, tsc'}}],
      output: JSON.stringify(
        {
          scripts: {
            lint: 'eslint . --cache',
            stylelint: 'stylelint --aei --rd "**/*.css"',
            test: 'jest',
            tsc: 'tsc',
          },
        },
        null,
        2,
      ),
    },
    // missing all scripts
    {
      code: JSON.stringify({
        scripts: {},
      }),
      filename: '/path/to/package/package.json',
      errors: [{messageId: 'missingScript', data: {script: 'lint, stylelint, test, tsc'}}],
      output: JSON.stringify(
        {
          scripts: {
            lint: 'eslint . --cache',
            stylelint: 'stylelint --aei --rd "**/*.css"',
            test: 'jest',
            tsc: 'tsc',
          },
        },
        null,
        2,
      ),
    },
    // when devDependencies includes @github-ui/tests, scripts should include test: ui-test
    {
      code: JSON.stringify({
        scripts: {
          lint: 'eslint . --cache',
          stylelint: 'stylelint --aei --rd "**/*.css"',
          test: 'jest',
          tsc: 'tsc',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      }),
      filename: '/path/to/package/package.json',
      errors: [{messageId: 'missingScript', data: {script: 'test'}}],
      output: JSON.stringify(
        {
          scripts: {
            lint: 'eslint . --cache',
            stylelint: 'stylelint --aei --rd "**/*.css"',
            test: 'ui-test',
            tsc: 'tsc',
          },
          devDependencies: {
            '@github-ui/tests': '*',
          },
        },
        null,
        2,
      ),
    },
  ],
})
