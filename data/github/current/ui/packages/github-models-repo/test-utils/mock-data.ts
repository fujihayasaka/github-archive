import {createRepository} from '@github-ui/current-repository/test-helpers'
import type {ModelRepoPayload} from '../types'

export function getModelsRoutePayload(): ModelRepoPayload {
  return {
    repository: createRepository(),
  }
}
