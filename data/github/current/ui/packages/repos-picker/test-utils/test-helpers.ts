import type {PropertyDefinition} from '@github-ui/repos-filter'

import type {PickerRepository} from '../types'

export const sampleDefinitions: PropertyDefinition[] = [
  {
    propertyName: 'enviroment',
    valueType: 'single_select',
    allowedValues: ['production', 'staging', 'development'],
  },
  {
    propertyName: 'database',
    valueType: 'single_select',
    allowedValues: ['mysql', 'postgres', 'mongodb'],
  },
  {
    propertyName: 'platform',
    valueType: 'string',
    allowedValues: undefined,
  },
]

const sampleReposNames = [
  'smile',
  'coco-banana',
  'pinacolado',
  'juicy-fruit',
  'orange-fruit',
  'grape-fruit',
  'apple-fruit',
  'pear-fruit',
  'kiwi-fruit',
  'banana-fruit',
  'bmw',
  'toyota',
].sort()

export const sampleRepos: PickerRepository[] = sampleReposNames.map(buildRepo)

export function buildRepo(name: string, index: number): PickerRepository {
  return {
    id: index + 1,
    nodeId: `node-${index + 1}`,
    name,
    ownerLogin: 'acme',
    visibility: name.includes('fruit') ? 'public' : 'private',
  }
}

export interface BillingRepo extends PickerRepository {
  seats: number
  openSource: boolean
}

export const sampleBillingRepos: BillingRepo[] = sampleReposNames.map(buildBillingRepo)

function buildBillingRepo(name: string, index: number): BillingRepo {
  return {
    ...buildRepo(name, index),
    seats: (index + 1) * 10,
    openSource: index % 2 === 0,
  }
}
