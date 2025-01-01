import {FormControl, InlineLink, Text} from '@primer/react-brand'

import type {GeneralConsentLanguageProps} from './types'
import {getAnalyticsEvent} from '../../../../../../lib/utils/analytics'

const copy = {
  preamble:
    'Yes please, I’d like GitHub and affiliates to use my information for personalized communications, targeted advertising and campaign effectiveness. See the',
  privacyStatementText: 'GitHub Privacy Statement',
  postamble: 'for more details.',
}

export default function Default({fieldName, privacyStatementHref, children}: GeneralConsentLanguageProps) {
  return (
    <FormControl>
      {/* Include children first for focus order */}
      {children}

      <FormControl.Label htmlFor={fieldName} data-testid="label">
        <Text weight="semibold">
          {copy.preamble}{' '}
          <InlineLink
            {...getAnalyticsEvent({
              action: copy.privacyStatementText,
              tag: 'hyperlink',
              context: 'consent_language_default',
              location: 'form',
            })}
            href={privacyStatementHref}
          >
            {copy.privacyStatementText}
          </InlineLink>{' '}
          {copy.postamble}
        </Text>
      </FormControl.Label>
    </FormControl>
  )
}
