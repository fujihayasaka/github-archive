import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'

// actual reference from the above data
export const MockFileDiffReference: FileDiffReference = {
  type: 'file-diff',
  id: 'diff-151a6b1b4e8a342656439799127992e10657c1d56fe4365c502178eb7c05f9ae',
  url: 'https://github.com/github/github/raw/b9ebe71d062d958adec437285bcfca71c864dfd1/ui/packages/copilot-code-chat/__tests__/use-file-diff-reference.test.tsx',
  baseFile: null,
  headFile: {
    type: 'file',
    repoID: 3,
    repoName: 'github',
    repoOwner: 'github',
    path: 'ui/packages/copilot-code-chat/__tests__/use-file-diff-reference.test.tsx',
    commitOID: 'b9ebe71d062d958adec437285bcfca71c864dfd1',
    url: 'https://github.com/github/github/raw/b9ebe71d062d958adec437285bcfca71c864dfd1/ui/packages/copilot-code-chat/__tests__/use-file-diff-reference.test.tsx',
    ref: 'b9ebe71d062d958adec437285bcfca71c864dfd1',
  },
} as const
