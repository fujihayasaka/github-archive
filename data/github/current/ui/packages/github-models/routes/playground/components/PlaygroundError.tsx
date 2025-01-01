import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon} from '@primer/octicons-react'
import {Box, Button, Flash, Link} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

export type PlaygroundErrorProps = {
  message: string
  showResetButton: boolean
  handleClearHistory: () => void
}

export const rateLimitedMessage = 'Rate limited, please try again later.'
export const rateLimitDocsUrl = 'https://docs.github.com/github-models/prototyping-with-ai-models#rate-limits'

export function PlaygroundError({message, showResetButton, handleClearHistory}: PlaygroundErrorProps) {
  return (
    <Box {...testIdProps('playground-error')} sx={{py: 2}}>
      <Flash
        variant="warning"
        sx={{
          display: 'grid',
          gridTemplateColumns: 'min-content 1fr minmax(0, auto)',
          gridTemplateRows: 'min-content',
          gridTemplateAreas: `'visual message actions'`,
          '@media screen and (max-width: 543.98px)': {
            gridTemplateColumns: 'min-content 1fr',
            gridTemplateRows: 'min-content min-content',
            gridTemplateAreas: `
        'visual message'
        '.      actions'
      `,
          },
        }}
      >
        <Box
          sx={{
            display: 'grid',
            alignSelf: 'center',
            gridArea: 'visual',
          }}
        >
          <Octicon icon={AlertIcon} />
        </Box>
        <Box
          sx={{
            fontSize: 1,
            lineHeight: '1.5',
            alignSelf: 'center',
            gridArea: 'message',
          }}
        >
          {message === rateLimitedMessage ? (
            <>
              <div />
              Sorry, you’re currently hitting{' '}
              <Link href={rateLimitDocsUrl} inline>
                usage rate limits
              </Link>
              .
            </>
          ) : (
            message
          )}
        </Box>
        {showResetButton && (
          <Box
            sx={{
              gridArea: 'actions',
              '@media screen and (max-width: 543.98px)': {
                alignSelf: 'start',
                margin: 'var(--base-size-8) 0 0 var(--base-size-8)',
              },
            }}
          >
            <Button onClick={handleClearHistory}>Reset chat</Button>
          </Box>
        )}
      </Flash>
    </Box>
  )
}
