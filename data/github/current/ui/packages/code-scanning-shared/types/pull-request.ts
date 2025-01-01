import type {Repository} from './repository'

export type PullRequest = {
  number: number
  repository: Repository
}
