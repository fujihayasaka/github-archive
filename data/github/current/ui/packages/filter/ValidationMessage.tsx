import {UnsafeHTMLText} from '@github-ui/safe-html/UnsafeHTML'
import {testIdProps} from '@github-ui/test-id-props'
import {Banner} from '@primer/react/experimental'

import {Strings} from './constants/strings'
import styles from './ValidationMessage.module.css'

interface ValidationMessageProps {
  id: string
  messages?: string[]
}

export const ValidationMessage = ({id, messages}: ValidationMessageProps) => {
  if (!messages || messages.length < 1) return null

  return (
    <Banner id={id} variant="warning" className={styles.Banner}>
      <Banner.Title>
        <span {...testIdProps('validation-error-count')}>{Strings.filterInvalid(messages.length)}</span>
      </Banner.Title>
      <div className={styles.Box_0}>
        <ul className={styles.Box_2} {...testIdProps('validation-error-list')}>
          {/* We are setting the HTML dangerously below in order to have <pre> tags show up as HTML properly */}
          {messages.map(message => (
            <li key={message.replaceAll(' ', '-')}>
              <UnsafeHTMLText
                html={message}
                domPurifyConfig={{ALLOWED_TAGS: ['pre'], ALLOWED_ATTR: [], ALLOW_DATA_ATTR: false}}
                className={styles.SafeHTMLBox_0}
              />
            </li>
          ))}
        </ul>
      </div>
    </Banner>
  )
}
