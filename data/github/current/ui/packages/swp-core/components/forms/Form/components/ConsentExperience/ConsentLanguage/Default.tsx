import {FormControl, InlineLink, Text} from '@primer/react-brand'

import type {GeneralConsentLanguageProps} from './types'

const copy = {
  preamble:
    'Yes please, I’d like GitHub and affiliates to use my information for personalized communications, targeted advertising and campaign effectiveness. See the',
  privacyStatementText: 'GitHub Privacy Statement',
  postamble: 'for more details.',
}

export default function Default({fieldName, privacyStatementHref, children}: GeneralConsentLanguageProps) {
  return (
    <FormControl>
      <FormControl.Label htmlFor={fieldName} data-testid="label">
        <Text weight="semibold">
          {copy.preamble} <InlineLink href={privacyStatementHref}>{copy.privacyStatementText}</InlineLink>{' '}
          {copy.postamble}
        </Text>
      </FormControl.Label>

      {children}
    </FormControl>
  )
}
