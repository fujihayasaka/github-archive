import {testIdProps} from '@github-ui/test-id-props'
import {useResponsiveValue} from '@primer/react'

import type {TokenUsage} from '@github-ui/github-models'
import {getDefaultTokenUsage} from '@github-ui/github-models/ModelUsage'
import type {RepoModel} from '../../../types'
import {CellResultPill} from './CellResultPill'

interface TokenUsageWidgetProps {
  tokenUsage?: TokenUsage
  model?: RepoModel
  className?: string
  variant: 'inline' | 'pills'
}

export function TokenUsageWidget({tokenUsage, className, variant = 'inline'}: TokenUsageWidgetProps) {
  const isMobile = useResponsiveValue({narrow: true}, false)

  const {lastMessageInputTokens, lastMessageOutputTokens, lastMessageLatency} = tokenUsage || getDefaultTokenUsage()

  const mainText = (
    <span className="fgColor-muted text-small">
      {variant === 'inline' ? (
        `Input: ${lastMessageInputTokens} • Output: ${lastMessageOutputTokens} • ${lastMessageLatency}ms`
      ) : (
        <>
          <CellResultPill
            key={`e-result-lastMessageInputTokens-${lastMessageInputTokens}`}
            {...testIdProps('playground-token-pill-input')}
          >
            {`Input: ${lastMessageInputTokens}`}
          </CellResultPill>
          <CellResultPill
            key={`e-result-lastMessageOutputTokens-${lastMessageOutputTokens}`}
            {...testIdProps('playground-token-pill-output')}
          >
            {`Output: ${lastMessageOutputTokens}`}
          </CellResultPill>
          <CellResultPill
            key={`e-result-lastMessageLatency-${lastMessageLatency}`}
            {...testIdProps('playground-token-pill-latency')}
          >
            {`Latency: ${lastMessageLatency}ms`}
          </CellResultPill>
        </>
      )}
    </span>
  )
  const mobileText = (
    <span className="fgColor-muted text-small text-right lh-condensed">
      In: {lastMessageInputTokens}
      <br />
      Out: {lastMessageOutputTokens}
    </span>
  )

  return (
    <>
      <span {...testIdProps('playground-token-usage')} className={className}>
        {isMobile ? mobileText : mainText}
      </span>
    </>
  )
}
