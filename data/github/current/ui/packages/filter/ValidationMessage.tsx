import {SafeHTMLBox} from '@github-ui/safe-html'
import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon} from '@primer/octicons-react'
import {Flash} from '@primer/react'

import {Strings} from './constants/strings'
import styles from './ValidationMessage.module.css'

interface ValidationMessageProps {
  id: string
  messages?: string[]
}

export const ValidationMessage = ({id, messages}: ValidationMessageProps) => {
  if (!messages || messages.length < 1) return null

  return (
    <Flash id={id} variant="warning" className={styles.Flash_0}>
      <AlertIcon className={styles.Octicon_0} />
      <div className={styles.Box_0}>
        <div className={styles.Box_1} {...testIdProps('validation-error-count')}>
          {Strings.filterInvalid(messages.length)}
        </div>
        <ul className={styles.Box_2} {...testIdProps('validation-error-list')}>
          {/* We are setting the HTML dangerously below in order to have <pre> tags show up as HTML properly */}
          {messages.map(message => (
            <SafeHTMLBox
              as="li"
              key={message.replaceAll(' ', '-')}
              unverifiedHTML={message}
              unverifiedHTMLConfig={{ALLOWED_TAGS: ['pre']}}
              className={styles.SafeHTMLBox_0}
            />
          ))}
        </ul>
      </div>
    </Flash>
  )
}
