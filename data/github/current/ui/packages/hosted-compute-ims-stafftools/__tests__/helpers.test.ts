import {validateImageDefinitionName, validateFeatureFlag} from '../helpers/utils'
import type {ImageDefinitionEnabled} from '../types/types'

test.each([
  ['Ubuntu 24.04', true],
  ['Ubuntu Latest (24.04)', true],
  ['', false],
  ['myimage?awfa', false],
])('validateImageDefinitionName(%s)', (name: string, expectedResult: boolean) => {
  const actualResult = validateImageDefinitionName(name)
  expect(actualResult).toBe(expectedResult)
})

test.each([
  ['Enabled', '', true],
  ['Disabled', '', true],
  ['Enabled', 'random????name', true],
  ['Disabled', 'random????name', true],
  ['FeatureFlag', '', false],
  ['FeatureFlag', 'myflag', false],
  ['FeatureFlag', 'ims_myflag', true],
  ['FeatureFlag', 'ims_my_long_flag', true],
  ['FeatureFlag', 'larger_runners_custom_image_generation', true],
])('validateFeatureFlag(%s)', (enabled: string, featureFlag: string, expectedResult: boolean) => {
  const actualResult = validateFeatureFlag(enabled as ImageDefinitionEnabled, featureFlag)
  expect(actualResult).toBe(expectedResult)
})
