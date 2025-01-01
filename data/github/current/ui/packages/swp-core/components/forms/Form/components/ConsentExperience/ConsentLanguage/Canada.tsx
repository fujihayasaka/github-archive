import {FormControl, InlineLink, Text} from '@primer/react-brand'
import type {GeneralConsentLanguageProps} from './types'
import {getAnalyticsEvent} from '../../../../../../lib/utils/analytics'

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
          <InlineLink
            {...getAnalyticsEvent({
              action: copy.settingsLinkText,
              tag: 'hyperlink',
              context: 'consent_language_canada',
              location: 'form',
            })}
            href={emailSubscriptionSettingsLinkHref}
          >
            {copy.settingsLinkText}
          </InlineLink>
          .{' '}
          <InlineLink
            {...getAnalyticsEvent({
              action: copy.privacyStatementText,
              tag: 'hyperlink',
              context: 'consent_language_canada',
              location: 'form',
            })}
            href={privacyStatementHref}
          >
            {copy.privacyStatementText}
          </InlineLink>
          .
        </Text>
      </FormControl.Label>

      {children}
    </FormControl>
  )
}
