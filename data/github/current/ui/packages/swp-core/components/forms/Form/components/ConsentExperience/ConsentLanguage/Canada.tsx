import {FormControl, InlineLink, Text} from '@primer/react-brand'
import type {GeneralConsentLanguageProps} from './types'

const copy = {
  preamble:
    'Yes, please, I’d like to hear from GitHub and its family of companies via email for personalized communications, targeted advertising, and campaign effectiveness. To withdraw consent or manage your contact preferences, visit the',
  preambleWithPhone:
    'Yes, please, I’d like to hear from GitHub and its family of companies via email and phone for personalized communications, targeted advertising, and campaign effectiveness. To withdraw consent or manage your contact preferences, visit the',
  privacyStatementText: 'GitHub Privacy Statement',
  settingsLinkText: 'Promotional Communications Manager',
}

export default function Canada({
  fieldName,
  hasPhone = false,
  privacyStatementHref,
  emailSubscriptionSettingsLinkHref,
  children,
}: GeneralConsentLanguageProps) {
  return (
    <FormControl>
      <FormControl.Label htmlFor={fieldName} data-testid="label">
        <Text weight="semibold">
          {hasPhone ? copy.preambleWithPhone : copy.preamble}{' '}
          <InlineLink href={emailSubscriptionSettingsLinkHref}>{copy.settingsLinkText}</InlineLink>.{' '}
          <InlineLink href={privacyStatementHref}>{copy.privacyStatementText}</InlineLink>.
        </Text>
      </FormControl.Label>

      {children}
    </FormControl>
  )
}
