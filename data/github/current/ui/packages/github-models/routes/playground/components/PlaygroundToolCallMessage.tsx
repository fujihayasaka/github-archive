import {testIdProps} from '@github-ui/test-id-props'
import type {PlaygroundMessage} from '../../../types'
import {useMemo} from 'react'
import {textFromMessageContent} from '../../../utils/message-content-helper'
import styles from './PlaygroundToolCallMessage.module.css'

type PlaygroundToolCallMessageProps = {
  message: PlaygroundMessage
}

export function PlaygroundToolCallMessage({message: {message}}: PlaygroundToolCallMessageProps) {
  const messageTextContent = useMemo(() => textFromMessageContent(message), [message])
  return (
    <div>
      <p className={styles.text} {...testIdProps('playground-tool-call-message')}>
        {messageTextContent}
      </p>
    </div>
  )
}
