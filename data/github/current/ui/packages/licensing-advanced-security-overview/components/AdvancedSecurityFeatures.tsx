import {useClickAnalytics} from '@github-ui/use-analytics'
import {CheckIcon} from '@primer/octicons-react'
import {Link, Stack, useResponsiveValue} from '@primer/react'
import type {SelfServeTrialInfo} from '../types/self-serve-trial-info'

const FEATURES = {
  'Secret Protection': [
    'Push protection to prevent secret leaks',
    'AI detection with a low rate of false positives',
    'Custom patterns for secrets',
    'Enterprise-grade policies',
    'Security overview for risk insights',
  ],
  'Code Security': [
    'Copilot Autofix for vulnerabilities',
    'Security findings for third-party tools',
    'Security campaigns to address security debt',
    'Enterprise-grade policies',
    'Security overview for risk insights',
  ],
}

export type AdvancedSecurityFeaturesProps = {
  selfServeTrialInfo?: SelfServeTrialInfo
  isTeams: boolean
  ghasFeaturesUrl: string
  trialDays?: number
}
export function AdvancedSecurityFeatures(props: AdvancedSecurityFeaturesProps) {
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const onLearnMoreClick = () => {
    sendClickAnalyticsEvent({
      category: 'advanced_security_self_serve_trial',
      action: 'click_security_features',
      label: 'ref_cta:features;ref_loc:enterprise_licensing',
    })
  }

  return (
    <Stack direction="vertical" gap="none" padding="spacious">
      {!props.selfServeTrialInfo?.trialExpired && !props.isTeams && (
        <p className="fgColor-muted">
          Enable GitHub Advanced Security for your enterprise now — the first {props.selfServeTrialInfo?.trialDays} days
          are on us.
        </p>
      )}
      <Stack direction={isMobile ? 'vertical' : 'horizontal'} gap="spacious">
        {Object.keys(FEATURES).map(title => (
          <Stack.Item grow key={title}>
            <Stack direction="vertical" gap="condensed">
              <h3>{title}</h3>
              <span className="text-small text-bold fgColor-muted">What&apos;s included</span>
              <ul className="list-style-none fgColor-muted d-flex flex-column gap-2">
                {FEATURES[title as keyof typeof FEATURES].map(feature => (
                  <li key={feature}>
                    <CheckIcon size={16} className="fgColor-success mr-1" />
                    {feature}
                  </li>
                ))}
              </ul>
              <Link href={props.ghasFeaturesUrl} onClick={onLearnMoreClick}>
                Learn more about {title}
              </Link>
            </Stack>
          </Stack.Item>
        ))}
      </Stack>
    </Stack>
  )
}
