import {RuleTester} from '@typescript-eslint/rule-tester'
import {afterAll, describe, it} from './tests'

RuleTester.afterAll = afterAll
RuleTester.describe = describe
RuleTester.describeSkip = describe.skip
RuleTester.it = it
RuleTester.itSkip = it.skip
// eslint-disable-next-line no-only-tests/no-only-tests
RuleTester.itOnly = it.only

export {
  type AtLeastVersionConstraint,
  type DependencyConstraint,
  type InvalidTestCase,
  noFormat,
  type RuleTesterConfig,
  type SemverVersionConstraint,
  type SuggestionOutput,
  type TestCaseError,
  type TestLanguageOptions,
  type ValidTestCase,
  type VersionConstraint,
} from '@typescript-eslint/rule-tester'
export {RuleTester}
