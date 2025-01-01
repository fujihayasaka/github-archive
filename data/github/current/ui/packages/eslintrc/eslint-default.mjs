import {baseConfig} from './eslint-base.mjs'
import i18nText from 'eslint-plugin-i18n-text'
import path, {dirname, join} from 'path'
import ssrFriendly from 'eslint-plugin-ssr-friendly'
import {fileURLToPath} from 'url'
import {readFileSync} from 'fs'
import {fixupPluginRules} from '@eslint/compat'
import {noRestrictedImportsRule, noRestrictedSyntaxRule} from './no-restricted.mjs'

const glob = (await import('glob')).default

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

const findDevPackages = () => {
  const uiPackagesGlob = join(__dirname, '../*/package.json')
  const packages = glob.sync(uiPackagesGlob, {ignore: 'node_modules/**', absolute: true})

  /** @type {string[]} */
  const defaultAcc = []

  return packages.reduce((acc, pkgName) => {
    const pkg = JSON.parse(readFileSync(pkgName, 'utf-8'))

    if (pkg.dev) acc.push(`${dirname(pkgName)}/**/*.{mjs,js,ts,tsx}`)

    return acc
  }, defaultAcc)
}

export const defaultConfig = [
  ...baseConfig,
  {
    rules: {
      'import/no-extraneous-dependencies': [
        'error',
        {
          devDependencies: [
            '**/__tests__/**/*.{ts,tsx}',
            '**/test-utils/**/*.{ts,tsx}',
            '**/*.stories.*',
            '**/jest.config.js',
            '**/eslint.config.mjs',
            '**/eslint-base.mjs',
            '**/eslint-default.mjs',
            '**/eslint-build.mjs',
            ...findDevPackages(),
          ],
          includeTypes: true,
          includeInternal: true,
        },
      ],
    },
  },
  {
    files: ['**/*.ts', '**/*.tsx'],
    plugins: {
      i18nText,
    },
    rules: {
      ...noRestrictedSyntaxRule([
        {
          selector: "TSNonNullExpression>CallExpression[callee.property.name='getAttribute']",
          message: "Please check for null or use  `|| ''` instead of `!` when calling `getAttribute`",
        },
      ]),
      'i18n-text/no-en': 'off',
    },
  },
  {
    ignores: ['**/__tests__/**', '**/test-utils/**'],
    files: ['**/*.ts', '**/*.tsx'],
    plugins: {
      'ssr-friendly': fixupPluginRules(ssrFriendly),
    },
    languageOptions: {
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    rules: {
      ...ssrFriendly.configs.recommended.rules,
      ...noRestrictedImportsRule({
        paths: [
          {
            // Only restrict ThemeProvider access outside of tests
            name: '@primer/react',
            importNames: ['ThemeProvider'],
            message: 'For `ThemeProvider`, do not use as it causes conflicting styles with SSR',
          },
        ],
      }),
    },
  },
]
