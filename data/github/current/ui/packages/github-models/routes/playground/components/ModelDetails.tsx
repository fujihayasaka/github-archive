import {testIdProps} from '@github-ui/test-id-props'
import {Box, Link} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import {InfoItem} from './InfoItem'

const tokenLabel = (n: number) => `${Math.round(n / 1000)}k`
const capitalize = (s: string) => `${s.charAt(0).toUpperCase()}${s.slice(1)}`

interface ModelDetailsProps {
  direction?: 'column' | 'row'
  model: Model
}

export function ModelDetails({direction = 'column', model}: ModelDetailsProps) {
  const rateLimitTier = model.rate_limit_tier
  const maxOutputTokens = model.max_output_tokens ? tokenLabel(model.max_output_tokens) : ''
  const maxInputTokens = tokenLabel(model.max_input_tokens)
  const inline = direction === 'row'
  const layout = {
    column: {
      flexDirection: 'column',
    },
    row: {
      flexDirection: 'row',
      flexWrap: 'wrap',
    },
  }[direction]

  return (
    <Box
      sx={{
        width: '100%',
        display: 'flex',
        gap: 2,
        ...layout,
      }}
      {...testIdProps('model-details')}
    >
      {!model.static_model && (
        <InfoItem {...testIdProps('context')} isInline={inline} label="Context">
          {maxInputTokens} input {maxOutputTokens ? <>&middot; {maxOutputTokens} output</> : ``}
        </InfoItem>
      )}

      {!model.static_model && (
        <InfoItem {...testIdProps('training-date')} isInline={inline} label="Training date">
          {model.training_data_date || 'Undisclosed'}
        </InfoItem>
      )}

      {rateLimitTier && (
        <InfoItem {...testIdProps('rate-limit-tier')} isInline={inline} label="Rate limit tier">
          <Link inline href="https://docs.github.com/en/github-models/prototyping-with-ai-models#rate-limits">
            {capitalize(rateLimitTier)}
          </Link>
        </InfoItem>
      )}

      {!model.static_model && (
        <InfoItem isInline={inline} label="Provider support">
          <Link inline href={`https://ai.azure.com/github/support/${model.name}`}>
            Azure support site
          </Link>
        </InfoItem>
      )}
    </Box>
  )
}
