import {MergeMethod} from '@github-ui/mergebox/types'
import {aliveChannels} from '@github-ui/mergebox/alive-channels-mocks'

import type {MergeBoxPartialProps} from '../MergeBoxPartial'

export function getMergeBoxPartialProps(): MergeBoxPartialProps {
  return {
    defaultMergeMethod: MergeMethod.MERGE,
    pullRequestId: 'PR_kwAEAQ',
    basePageDataUrl: 'monalisa/pull/1',
    viewerLogin: 'monalisa',
    helpUrl: 'https://docs.github.com',
    enabledFeatures: {},
    channels: aliveChannels,
  }
}
