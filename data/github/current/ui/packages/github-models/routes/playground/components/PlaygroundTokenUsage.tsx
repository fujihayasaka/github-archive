import {clsx} from 'clsx'
import {testIdProps} from '@github-ui/test-id-props'
import {PublisherAvatar} from '../../../components/PublisherAvatar'
import type {ModelState} from '../../../types'
import {getMaxOutputTokensParameterValue, getMostRecentUserMessageTimestamp} from '../../../utils/model-state'
import {RelativeTime} from '@primer/react'

interface PlaygroundTokenUsageProps {
  modelState: ModelState
  border?: boolean
}

export function PlaygroundTokenUsage({
  modelState: {
    catalogData: model,
    messages,
    modelInputSchema,
    parameters,
    tokenUsage: {lastMessageInputTokens, lastMessageOutputTokens, totalInputTokens, totalOutputTokens},
    usageStats: {lastMessageLatency, totalLatency},
  },
  border = false,
}: PlaygroundTokenUsageProps) {
  const {max_output_tokens: maxOutputTokens, max_input_tokens: maxInputTokens, friendly_name: friendlyName} = model
  const maxOutputTokensParamValue = getMaxOutputTokensParameterValue(modelInputSchema, parameters)
  const mostRecentUserMessageDate = getMostRecentUserMessageTimestamp(messages)
  return (
    <div className={clsx('d-flex', 'flex-1', 'p-3', border && 'border rounded-2')}>
      <div className="d-flex flex-column gap-3">
        <h2 className="h5 d-flex gap-2">
          <PublisherAvatar logoUrl={model.logo_url} darkModeIcon={model.dark_mode_icon} publisher={model.publisher} />
          <span {...testIdProps('model-name')} className="text-bold">
            {friendlyName}
          </span>
          {mostRecentUserMessageDate && (
            <RelativeTime
              {...testIdProps('latest-user-message-time')}
              className="text-normal fgColor-muted"
              date={mostRecentUserMessageDate}
              format="relative"
            />
          )}
        </h2>
        <div {...testIdProps('playground-usage-input-tokens')}>
          <h3 className="h5">Input Tokens</h3>
          <ul className="ml-3 color-fg-muted">
            <li>Most recent message: {lastMessageInputTokens.toLocaleString()}</li>
            <li>Total: {totalInputTokens.toLocaleString()}</li>
            <li {...testIdProps('max-input-tokens')}>Limit: {maxInputTokens.toLocaleString()}</li>
          </ul>
        </div>
        <div {...testIdProps('playground-usage-output-tokens')}>
          <h3 className="h5">Output Tokens</h3>
          <ul className="ml-3 color-fg-muted">
            <li>Most recent message: {lastMessageOutputTokens.toLocaleString()}</li>
            <li>Total: {totalOutputTokens.toLocaleString()}</li>
            {maxOutputTokens !== null && (
              <li {...testIdProps('max-output-tokens')}>
                Limit: {maxOutputTokens.toLocaleString()}
                {maxOutputTokensParamValue !== undefined && (
                  <span> &middot; {maxOutputTokensParamValue.toLocaleString()} for parameter</span>
                )}
              </li>
            )}
          </ul>
        </div>
        <div {...testIdProps('playground-usage-stats')}>
          <h3 className="h5">Latency</h3>
          <ul className="ml-3 color-fg-muted">
            <li>Most recent message: {lastMessageLatency} ms</li>
            <li>Total: {totalLatency} ms</li>
          </ul>
        </div>
      </div>
    </div>
  )
}
