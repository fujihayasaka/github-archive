import {Text, Box} from '@primer/react'
import {AlertIcon} from '@primer/octicons-react'
import {testIdProps} from '@github-ui/test-id-props'

export function MissingCombinationPlaceholder() {
  return (
    <Box
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        gap: 2,
        justifyContent: 'center',
        alignItems: 'center',
      }}
      {...testIdProps('missing-combination-placeholder')}
    >
      <Box sx={{color: 'attention.fg'}}>
        <AlertIcon size={16} />
      </Box>
      <Text as="h2" sx={{fontWeight: 'bold', textAlign: 'center', fontSize: 2, pt: 2}}>
        Documentation for this language and SDK combination is unavailable
      </Text>
      <Text as="p" sx={{color: 'fg.muted', textAlign: 'center'}}>
        Try a different combination
      </Text>
    </Box>
  )
}
