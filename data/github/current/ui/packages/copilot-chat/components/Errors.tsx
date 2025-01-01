import {MarkdownRenderer} from '@github-ui/copilot-markdown'
import {testIdProps} from '@github-ui/test-id-props'
import {AlertFillIcon, LinkIcon, MarkGithubIcon, XIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useCallback, useState} from 'react'

import {buildMessage} from '../utils/copilot-chat-helpers'
import type {CopilotChatManager} from '../utils/copilot-chat-manager'
import type {AgentUnauthorizedChatError, CopilotAgentError} from '../utils/copilot-chat-types'
import {capitalize} from '../utils/string'
import styles from './ChatMessage.module.css'
import {useChatMessage} from './ChatMessageContext'

export function ErrorMessage({manager}: {manager: CopilotChatManager}) {
  const {message} = useChatMessage()
  const {error} = message
  if (!error) return null
  switch (error.type) {
    case 'agentUnauthorized':
      return <AgentUnauthorizedError error={error} manager={manager} />
    case 'agentRequest':
      return <AgentErrors errors={[error.details]} />
    default:
      return (
        <Banner
          {...testIdProps('error-message-banner')}
          title="Error"
          hideTitle
          description={error.message || 'Something went wrong'}
          variant="warning"
        />
      )
  }
}

function AgentUnauthorizedError({error, manager}: {error: AgentUnauthorizedChatError; manager: CopilotChatManager}) {
  const {details} = error
  const [dismissed, setDismissed] = useState(false)
  const onDismiss = useCallback(() => {
    setDismissed(true)
    manager.dispatch({
      type: 'MESSAGE_ADDED',
      message: buildMessage({
        role: 'user',
        content: `Dismissed the connection with ${details.name}.`,
        mediaContent: [],
        parentMessageID: manager.FindLastMessageID(), // Attach client skill request to any last message in current subthread
      }),
    })
    manager.dispatch({
      type: 'MESSAGE_ADDED',
      message: buildMessage({
        role: 'assistant',
        content: `I was unable to connect you to ${details.name} because you cancelled the authentication.`,
        mediaContent: [],
        parentMessageID: manager.FindLastMessageID(), // Attach client skill request to any last message in current subthread
      }),
    })
  }, [details.name, manager])

  return (
    <div
      className="position-relative d-flex flex-column flex-items-center gap-3 border rounded-2 p-5"
      {...testIdProps('agent-unauthorized-error')}
    >
      {!dismissed && (
        // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
        <IconButton
          aria-label="Close"
          className="position-absolute top-0 right-0 mt-2 mr-2"
          icon={XIcon}
          onClick={onDismiss}
          variant="invisible"
          unsafeDisableTooltip
        />
      )}
      <div className="d-flex flex-items-center gap-2">
        <MarkGithubIcon size={48} className="border circle borderColor-muted" />
        <LinkIcon className="fgColor-muted" />
        <img
          className={clsx('avatar', styles.agentUnauthorizedAvatar, 'border circle borderColor-muted')}
          src={details.avatar_url}
          alt={`icon for ${details.name}`}
        />
      </div>
      <p className="h4 m-0 text-center">Connect with {details.name}</p>
      <p className="fgColor-muted text-center">
        To use the {details.name} extension, you’ll need to connect your GitHub account to your {details.name} account.
      </p>
      {!dismissed && (
        <>
          <Button
            as="a"
            variant="primary"
            size="large"
            className="width-full"
            href={details.authorize_url}
            rel="noopener"
            target="_blank"
          >
            Connect
          </Button>
          <p className="fgColor-muted text-center f6 m-0">Click connect to be redirected to {details.authorize_url}</p>
        </>
      )}
    </div>
  )
}

export function AgentErrors({errors}: {errors: CopilotAgentError[]}) {
  return (
    <div className="d-flex flex-column gap-2">
      {errors.map((error, i) => (
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <div className="p-3 border rounded-2" key={i}>
          <div className="text-bold">
            <AlertFillIcon className="mr-1 fgColor-attention" /> {errorTitle(error)}
          </div>
          <MarkdownRenderer markdown={error.message} />
        </div>
      ))}
    </div>
  )
}

function errorTitle(error: CopilotAgentError) {
  if (error.type === 'http') {
    return `${error.code} ${error.identifier}`
  } else {
    return `${capitalize(error.type)} error`
  }
}
