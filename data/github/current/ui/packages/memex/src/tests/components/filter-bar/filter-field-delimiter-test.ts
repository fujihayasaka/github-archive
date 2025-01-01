import {isFeatureEnabled} from '@github-ui/feature-flags'
import {BlockType, FilterOperator} from '@github-ui/filter'
import {StateFilterProvider} from '@github-ui/filter/providers'

import {fieldDelimiterValidator} from '../../../client/components/filter-bar/helpers/filter-field-delimiter'

const mockedIsFeatureEnabled = jest.mocked(isFeatureEnabled)
jest.mock('@github-ui/feature-flags', () => ({isFeatureEnabled: jest.fn()}))

const block = {
  id: 1,
  type: BlockType.Filter,
  raw: 'test',
  provider: new StateFilterProvider(),
  key: {value: 'test', valid: true},
  value: {values: [], raw: ''},
  operator: FilterOperator.Is,
}
const validationResults = [
  {
    valid: false,
    value: 'test',
    startIndex: 0,
    endIndex: 4,
    hasCaret: false,
    validations: undefined,
  },
]

describe('filter field delimiter for a FilterBlock', () => {
  beforeEach(() => {
    mockedIsFeatureEnabled.mockRestore()
  })

  it('does nothing if the feature flag is not enabled', () => {
    mockedIsFeatureEnabled.mockReturnValue(false)
    expect(fieldDelimiterValidator(block, validationResults)).toEqual(validationResults)
  })

  it('allows whitespace "at the end" of a `FilterBlock`', () => {
    mockedIsFeatureEnabled.mockReturnValue(true)

    // filter blocks are tokenized by whitespace
    const raw = 'label:bug,"bug :bug:",docs repo:github/github'
    const testBlock = {...block, raw, key: {value: raw, valid: true}}
    const [result] = validationResults
    const testResult = [
      {...result, value: 'bug'},
      {...result, value: 'bug :bug:'},
      {...result, value: 'docs'},
      {...result, valid: true, value: ''},
      {...result, valid: true, value: 'github/github'},
      {...result, valid: true, value: ''},
    ]

    const delimiterValidationResult = fieldDelimiterValidator(testBlock, testResult).pop()
    expect(delimiterValidationResult!.valid).toBeTruthy()
  })

  it('allows a (single) comma "at the end" of a `FilterBlock`', () => {
    mockedIsFeatureEnabled.mockReturnValue(true)

    // filter blocks are tokenized by whitespace
    const raw = 'label:bug,"bug :bug:",docs, repo:github/github,'
    const testBlock = {...block, raw, key: {value: raw, valid: true}}
    const [result] = validationResults
    const testResult = [
      {...result, valid: true, value: 'bug'},
      {...result, valid: true, value: 'bug :bug:'},
      {...result, valid: true, value: 'docs'},
      {...result, valid: false, value: ''},
      {...result, valid: true, value: 'github/github'},
      {...result, valid: false, value: ''},
    ]

    const delimiterValidationResult = fieldDelimiterValidator(testBlock, testResult).pop()
    expect(delimiterValidationResult!.valid).toBeTruthy()
  })
})
