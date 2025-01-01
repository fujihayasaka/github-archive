import {validateImageDefinitionName, validateFeatureFlag, splitCuratedImageDefinitions} from '../helpers/utils'
import type {ImageDefinition, ImageDefinitionEnabled} from '../types/types'

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
])('validateFeatureFlag(%s)', (enabled: string, featureFlag: string, expectedResult: boolean) => {
  const actualResult = validateFeatureFlag(enabled as ImageDefinitionEnabled, featureFlag)
  expect(actualResult).toBe(expectedResult)
})

test('splitCuratedImageDefinitions', () => {
  const imagesList: ImageDefinition[] = [
    {
      id: 1,
      name: '',
      osType: 'Linux',
      architecture: 'X64',
      enabled: true,
      featureFlag: '',
      updatedAt: '',
      createdAt: '',
      imageVersionsCount: 0,
      pointsToImageDefinitionId: 1,
    },
    {
      id: 2,
      name: '',
      osType: 'Linux',
      architecture: 'X64',
      enabled: true,
      featureFlag: '',
      updatedAt: '',
      createdAt: '',
      imageVersionsCount: 0,
      pointsToImageDefinitionId: 0,
    },
    {
      id: 3,
      name: '',
      osType: 'Linux',
      architecture: 'X64',
      enabled: true,
      featureFlag: '',
      updatedAt: '',
      createdAt: '',
      imageVersionsCount: 0,
      pointsToImageDefinitionId: 0,
    },
  ]

  const actualResult = splitCuratedImageDefinitions(imagesList)
  expect(actualResult.imagePointersList).toHaveLength(1)
  expect(actualResult.imageDefinitionsList).toHaveLength(2)
  expect(actualResult.imagePointersList[0]?.id).toBe(1)
  expect(actualResult.imageDefinitionsList[0]?.id).toBe(2)
  expect(actualResult.imageDefinitionsList[1]?.id).toBe(3)
})
