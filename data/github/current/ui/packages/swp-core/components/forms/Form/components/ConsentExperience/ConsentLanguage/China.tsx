import {FormControl, InlineLink, Stack, Text} from '@primer/react-brand'

import type {GeneralConsentLanguageProps} from './types'

const copy = {
  preamble:
    'Yes please, I’d like GitHub and affiliates to use my information for personalized communications, targeted advertising and campaign effectiveness. See the',
  privacyStatementText: 'GitHub Privacy Statement',
  postamble: 'for more details.',
}

export default function China({fieldName, privacyStatementHref, children}: GeneralConsentLanguageProps) {
  return (
    <Stack direction="vertical" padding="none" gap="condensed">
      <FormControl>
        <FormControl.Label htmlFor={fieldName} data-testid="label">
          <Text weight="semibold">
            {copy.preamble} <InlineLink href={privacyStatementHref}>{copy.privacyStatementText}</InlineLink>{' '}
            {copy.postamble}
          </Text>
        </FormControl.Label>
        {children}
      </FormControl>

      <Text variant="muted">
        Participation requires transferring your personal data to other countries in which GitHub operates, including
        the United States. By submitting this form, you agree to the transfer of your data outside of China.
      </Text>
    </Stack>
  )
}
