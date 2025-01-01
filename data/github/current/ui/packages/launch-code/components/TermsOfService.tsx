import {Box, InlineLink, Text} from '@primer/react-brand'

export const TermsOfService = () => {
  return (
    <Box>
      <Text as="p" size="100" variant="muted">
        By creating an account, you agree to the{` `}
        <InlineLink href="/site/terms" target="_blank" rel="noopener">
          Terms of Service
        </InlineLink>
        . For more information about GitHub&#39;s privacy practices, see the{` `}
        <InlineLink href="/site/privacy" target="_blank" rel="noopener">
          GitHub Privacy Statement
        </InlineLink>
        . We&#39;ll occasionally send you account-related emails.
      </Text>
    </Box>
  )
}
