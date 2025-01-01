import {RENDERABLE_REFERENCE_TYPES} from '@github-ui/copilot-chat/components/ChatReferences'
import {ReferenceToken} from '@github-ui/copilot-chat/components/ReferenceToken'
import {referenceID} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {FocusKeys} from '@primer/behaviors'
import {useFocusZone} from '@primer/react'
import {clsx} from 'clsx'
import {useRef} from 'react'

import styles from './ChatMessageReferences.module.css'

interface ChatReferenceTokensProps {
  references: CopilotChatReference[]
  size: 'small' | 'medium'
  className?: string
}

export function ChatMessageReferences({references, size, className}: ChatReferenceTokensProps) {
  const renderableReferences = references.filter(reference => RENDERABLE_REFERENCE_TYPES.includes(reference.type))

  const containerRef = useRef<HTMLDivElement>(null)
  useFocusZone(
    {
      containerRef,
      bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
      focusInStrategy: 'previous',
      focusOutBehavior: 'stop',
    },
    [renderableReferences],
  )

  if (renderableReferences.length === 0) return null

  return (
    <div ref={containerRef} role="toolbar" aria-label="References" className={clsx(styles.container, className)}>
      {renderableReferences.map(reference => (
        <ReferenceToken reference={reference} key={referenceID(reference)} size={size} />
      ))}
    </div>
  )
}
