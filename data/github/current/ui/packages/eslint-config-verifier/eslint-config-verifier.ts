import {loadESLint} from 'eslint'
import {fullPathFromRoot, globFromRoot} from '@github-ui/client-build-tools/path-utils'
import {isDeepStrictEqual} from 'node:util'

const packageName = 'react-sandbox'
const packagePath = `ui/packages/${packageName}`
const fullPackagePath = fullPathFromRoot(packagePath)
const packageFiles = globFromRoot(`${packagePath}/**/*.{ts,tsx,js,jsx,mjs,cjs}`)

const NAMESPACE_MATCHER: {[key: string]: string} = {
  eslintComments: 'eslint-comments',
  'eslint-comments': 'eslintComments',
  wc: 'custom-elements',
  'custom-elements': 'wc',
  importPlugin: 'import',
  import: 'importPlugin',
  'no-only-tests': 'noOnlyTestsPlugin',
  noOnlyTestsPlugin: 'no-only-tests',
  prettierPlugin: 'prettier',
  prettier: 'prettierPlugin',
  escompatPlugin: 'escompat',
  escompat: 'escompatPlugin',
  jsxA11yPlugin: 'jsx-a11y',
  'jsx-a11y': 'jsxA11yPlugin',
}

const RULE_MATCHER: {[key: string]: string} = {
  'github/filenames-match-regex': 'filenames/match-regex',
  'filenames/match-regex': 'github/filenames-match-regex',
}

type RuleValue = string | number | unknown

interface RuleDiff {
  legacy: string | RuleValue[]
  flat: string | RuleValue[]
}
interface ESLintConfig {
  rules: {[key: string]: RuleValue[]}
}

const differences: {[ruleName: string]: {[fileName: string]: RuleDiff}} = {}

const valuesAreEquivalent = (legacyValue: RuleValue, flatValue: RuleValue) => {
  switch (legacyValue) {
    case 0:
    case 'off':
      return flatValue === 0 || flatValue === 'off'
    case 1:
    case 'warn':
      return flatValue === 1 || flatValue === 'warn'
    case 2:
    case 'error':
      return flatValue === 2 || flatValue === 'error'
    default:
      return isDeepStrictEqual(legacyValue, flatValue)
  }
}

const rulesAreEqual = (legacyRule: RuleValue[], flatRule: RuleValue[]) => {
  if (legacyRule.length !== flatRule.length) return false

  for (let i = 0; i < legacyRule.length; i++) {
    if (!valuesAreEquivalent(legacyRule[i], flatRule[i])) return false
  }

  return true
}

const findEquivalentRule = (rules: {[key: string]: RuleValue[]}, ruleName: string): RuleValue[] | undefined => {
  if (rules[ruleName]) return rules[ruleName]

  const possibleRuleName = RULE_MATCHER[ruleName]

  if (possibleRuleName) return rules[possibleRuleName]

  const [namespace, ...rest] = ruleName.split('/')

  if (!namespace) return

  const transformedNamespace = NAMESPACE_MATCHER[namespace]

  if (!transformedNamespace) return

  const transformedName = `${transformedNamespace}/${rest.join('/')}`

  return rules[transformedName]
}

;(async () => {
  const FlatESLint = await loadESLint({useFlatConfig: true})
  const LegacyESLint = await loadESLint({useFlatConfig: false})

  const flat = new FlatESLint({cwd: fullPackagePath})
  const legacy = new LegacyESLint()

  const findConfigDifferences = async (filePath: string) => {
    const flatConfig = (await flat.calculateConfigForFile(filePath)) as ESLintConfig
    const legacyConfig = (await legacy.calculateConfigForFile(filePath)) as ESLintConfig

    if (!flatConfig || !legacyConfig) return

    for (const [ruleName, flatRule] of Object.entries(flatConfig.rules)) {
      const legacyRule = findEquivalentRule(legacyConfig.rules, ruleName)

      if (!legacyRule) {
        differences[ruleName] ||= {}
        differences[ruleName][filePath] = {
          legacy: 'missing',
          flat: flatRule,
        }
      } else if (!rulesAreEqual(legacyRule, flatRule)) {
        differences[ruleName] ||= {}
        differences[ruleName][filePath] = {
          legacy: legacyRule,
          flat: flatRule,
        }
      }
    }

    for (const [ruleName, legacyRule] of Object.entries(legacyConfig.rules)) {
      const flatRule = findEquivalentRule(flatConfig.rules, ruleName)

      if (!flatRule) {
        differences[ruleName] ||= {}
        differences[ruleName][filePath] = {
          legacy: legacyRule,
          flat: 'missing',
        }
      }
    }
  }

  const promises = packageFiles.map(findConfigDifferences)

  await Promise.all(promises)

  console.log(JSON.stringify(differences, null, 2))
})()
