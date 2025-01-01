import {InlineLink, Text} from '@primer/react-brand'

import type {GeneralConsentLanguageProps} from './types'
import {getAnalyticsEvent} from '../../../../../../lib/utils/analytics'

const copy = {
  preamble: 'I will receive personalized communications and targeted advertising from GitHub and affiliates. See the',
  privacyStatementText: 'GitHub Privacy Statement',
  postamble: 'for more details.',
}

export default function UnitedStates({children, privacyStatementHref}: GeneralConsentLanguageProps) {
  return (
    <>
      {children}
      <Text>
        {copy.preamble}{' '}
        <InlineLink
          {...getAnalyticsEvent({
            action: copy.privacyStatementText,
            tag: 'hyperlink',
            context: 'consent_language_united_states',
            location: 'form',
          })}
          href={privacyStatementHref}
        >
          {copy.privacyStatementText}
        </InlineLink>{' '}
        {copy.postamble}
      </Text>
    </>
  )
}
