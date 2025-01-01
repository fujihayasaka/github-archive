import type {RefType} from '@github-ui/ref-selector'
import type {RefSelectorPartialProps} from '../RefSelectorPartial'

export const refs = {
  tag: ['0.0.1', '0.1.1', '1.1.1'],
  branch: ['main', 'test', 'my-branch'],
} as const

export function getRefSelectorPartialProps(): RefSelectorPartialProps {
  return {
    cacheKey: 'cacheKey',
    canCreate: true,
    defaultBranch: 'main',
    ownerLogin: 'owner',
    repoName: 'repo',
    initialRef: 'main',
    types: ['branch', 'tag'],
  }
}

export function getRefsResponse(type: RefType) {
  return {refs: refs[type], cacheKey: type}
}
