import {testIdProps} from '@github-ui/test-id-props'
import {Link} from '@primer/react'
import type {Model} from '@github-ui/marketplace-common'
import {InfoItem} from './InfoItem'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

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
  const billingUiEnabled = useFeatureFlag('github_models_billing_ui')
  const inline = direction === 'row'
  const flexWrap = direction === 'row' ? 'flex-wrap' : 'flex-nowrap'

  return (
    <div className={`d-flex flex-${direction} ${flexWrap} gap-2`} {...testIdProps('model-details')}>
      <InfoItem {...testIdProps('context')} isInline={inline} label="Context">
        {maxInputTokens} input {maxOutputTokens ? <>&middot; {maxOutputTokens} output</> : ``}
      </InfoItem>
      <InfoItem {...testIdProps('training-date')} isInline={inline} label="Training date">
        {model.training_data_date || 'Undisclosed'}
      </InfoItem>

      {rateLimitTier && (
        <InfoItem
          {...testIdProps('rate-limit-tier')}
          isInline={inline}
          label={billingUiEnabled ? 'Free rate limit tier' : 'Rate limit tier'}
        >
          <Link
            inline
            href="https://docs.github.com/en/github-models/prototyping-with-ai-models#rate-limits"
            tabIndex={0}
          >
            {capitalize(rateLimitTier)}
          </Link>
        </InfoItem>
      )}

      {billingUiEnabled && (
        <InfoItem isInline={inline} label="Pricing">
          <Link inline href="https://gh.io/github-models-pricing" tabIndex={0}>
            View pricing
          </Link>
        </InfoItem>
      )}

      <InfoItem isInline={inline} label="Provider support">
        <Link inline href={`https://ai.azure.com/github/support/${model.name}`} tabIndex={0}>
          Azure support site
        </Link>
      </InfoItem>
    </div>
  )
}
