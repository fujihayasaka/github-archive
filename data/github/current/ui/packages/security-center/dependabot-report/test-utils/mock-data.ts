import type {SecurityCenterDependabotMetricsProps} from '../SecurityCenterDependabotMetrics'

export function getSecurityCenterDependabotMetricsProps(): SecurityCenterDependabotMetricsProps {
  return {
    initialQuery: '',
    feedbackLink: {
      text: 'Give feedback',
      url: '#',
    },
    showIncompleteDataWarning: false,
    incompleteDataWarningDocHref: 'https://docs.github.com/en',
    filterProviders: [],
    allowedDependabotQualifiers: ['is', 'has', 'severity', 'epss_percentage'],
  }
}
