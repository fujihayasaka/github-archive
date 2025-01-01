import type {IndexModelsPayload} from '../../../types'
import {mockModel} from '../../playground/__tests__/mocks'
import {mockCategory} from '@github-ui/marketplace-common/mock-data'

export function mockModelsIndexRoutePayload(overrides: Partial<IndexModelsPayload> = {}): IndexModelsPayload {
  const basePayload: IndexModelsPayload = {
    models: [mockModel],
    categories: {apps: [mockCategory()], actions: [mockCategory()]},
  }
  return {...basePayload, ...overrides}
}
