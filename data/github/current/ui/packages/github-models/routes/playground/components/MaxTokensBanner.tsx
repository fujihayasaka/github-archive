import {useEffect} from 'react'
import {Banner} from '@primer/react/experimental'
import {testIdProps} from '@github-ui/test-id-props'
import type {ModelState} from '../../../types'
import {hasReachedMaxOutputTokens} from '../../../utils/model-state'
import {announce} from '@github-ui/aria-live'

interface MaxTokensBannerProps {
  modelState: ModelState
}

const maxTokensReachedMessage = 'You have reached the maximum tokens limit for this output.'

export function MaxTokensBanner({modelState: {isLoading, ...modelState}}: MaxTokensBannerProps) {
  const showBanner = !isLoading && hasReachedMaxOutputTokens(modelState)

  useEffect(() => {
    if (showBanner) announce(maxTokensReachedMessage)
  }, [showBanner])

  if (!showBanner) {
    return null
  }

  return (
    <Banner {...testIdProps('max-tokens-banner')} className="mb-3" title="Max output tokens reached" hideTitle>
      {maxTokensReachedMessage}
    </Banner>
  )
}
