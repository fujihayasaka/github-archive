import {Dialog, Button, useResponsiveValue} from '@primer/react'
import {useState} from 'react'
import type {ModelState} from '../../../types'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {testIdProps} from '@github-ui/test-id-props'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {supportsTokenCounting} from '../../../utils/model-capability'
import {PlaygroundTokenUsage} from './PlaygroundTokenUsage'

interface PlaygroundTokenUsageWidgetProps {
  modelState: ModelState
  position: number
}

export function PlaygroundTokenUsageWidget({modelState, position}: PlaygroundTokenUsageWidgetProps) {
  const {lastMessageInputTokens, totalInputTokens, lastMessageOutputTokens, totalOutputTokens} = modelState.tokenUsage
  const usageStats = modelState.usageStats
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const [isOpen, setIsOpen] = useState(false)
  const {models: modelStates} = usePlaygroundState()
  const isMobile = useResponsiveValue({narrow: true}, false)

  const shouldRenderTokenUsage = useFeatureFlag('github_models_playground_token_usage')
  const renderBorders = modelStates.length > 1

  const handleOpen = () => {
    setIsOpen(!isOpen)
    sendClickAnalyticsEvent({
      category: 'github_models_playground',
      action: 'click_to_open_usage_info',
    })
  }

  if (!shouldRenderTokenUsage) {
    return null
  }

  if (!supportsTokenCounting(modelState.catalogData)) {
    return null
  }

  const mainText = (
    <div className="fgColor-muted text-small">
      Input: {lastMessageInputTokens}/{totalInputTokens} • Output: {lastMessageOutputTokens}/{totalOutputTokens} •{' '}
      {usageStats.lastMessageLatency}ms
    </div>
  )
  const mobileText = (
    <div className="fgColor-muted text-small text-right lh-condensed">
      In: {lastMessageInputTokens}/{totalInputTokens}
      <br />
      Out: {lastMessageOutputTokens}/{totalOutputTokens}
    </div>
  )

  return (
    <>
      <Button
        {...testIdProps('playground-token-usage')}
        variant="invisible"
        size="small"
        aria-label="Show usage info"
        onClick={() => handleOpen()}
      >
        {isMobile ? mobileText : mainText}
      </Button>
      {isOpen && (
        <Dialog title="Model usage insights" role="dialog" onClose={() => setIsOpen(false)}>
          <div className="d-flex gap-3">
            {modelStates.map(model => (
              <PlaygroundTokenUsage
                key={`pg-usage-${position}-${model.catalogData.id}`}
                modelState={model}
                border={renderBorders}
              />
            ))}
          </div>
        </Dialog>
      )}
    </>
  )
}
