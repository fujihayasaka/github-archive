import {SafeHTMLText} from '@github-ui/safe-html'
import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon} from '@primer/octicons-react'
import {Box, Flash, Octicon} from '@primer/react'

import {Strings} from './constants/strings'
import styles from './ValidationMessage.module.css'

interface ValidationMessageProps {
  id: string
  messages?: string[]
}

export const ValidationMessage = ({id, messages}: ValidationMessageProps) => {
  if (!messages || messages.length < 1) return null

  return (
    <Flash
      id={id}
      variant="warning"
      sx={{
        py: 2,
        pl: '12px',
        pr: 3,
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'flex-start',
        justifyContent: 'flex-start',
      }}
    >
      <Octicon icon={AlertIcon} sx={{mt: '2px'}} />
      <Box sx={{display: 'flex', flexDirection: 'column'}}>
        <Box sx={{fontWeight: 500}} {...testIdProps('validation-error-count')}>
          {Strings.filterInvalid(messages.length)}
        </Box>
        <Box as="ul" sx={{ml: 3}} {...testIdProps('validation-error-list')}>
          {/* We are setting the HTML dangerously below in order to have <pre> tags show up as HTML properly */}
          {messages.map(message => (
            <li key={message.replaceAll(' ', '-')}>
              <SafeHTMLText
                unverifiedHTML={message}
                unverifiedHTMLConfig={{ALLOWED_TAGS: ['pre'], ALLOWED_ATTR: [], ALLOW_DATA_ATTR: false}}
                className={styles.SafeHTMLBox_0}
              />
            </li>
          ))}
        </Box>
      </Box>
    </Flash>
  )
}
