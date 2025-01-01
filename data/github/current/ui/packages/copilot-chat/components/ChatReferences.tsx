import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {ActionList, Details} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import type React from 'react'

import {isDocset, referenceID} from '../utils/copilot-chat-helpers'
import type {CopilotChatReference} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {docLanguages} from '../utils/language-info'
import {OutputReference} from './ChatReference'
import styles from './ChatReferences.module.css'
import {FigmaChatReference} from './FigmaChatReference'
import {ReferenceToken} from './ReferenceToken'
import {Toolbar} from './Toolbar'

let renderableReferenceTypesCache: ReadonlySet<CopilotChatReference['type']> | undefined = undefined

/** Set of reference types that should be rendered on chat messages. */
export const chatMessageRenderableReferenceTypes = () =>
  (renderableReferenceTypesCache ??= new Set([
    'file',
    'file-diff',
    'folder',
    'snippet',
    'symbol',
    'commit',
    'pull-request',
    'third-party',
    'repo-instructions',
    'figma',
    ...(copilotFeatureFlags.topicsAsReferences ? (['repository', 'docset'] as const) : []),
  ]))

export interface ChatMessageReferencesListProps {
  references: CopilotChatReference[]
  onToggle?: (e: React.SyntheticEvent) => void
  isImmersive?: boolean
  className?: string
}

export function ChatMessageReferencesList({
  references,
  onToggle,
  isImmersive,
  className,
}: ChatMessageReferencesListProps) {
  const state = useChatState() as ReturnType<typeof useChatState> | undefined // if we're run in tests without context, this will be undefined
  const renderableReferences = references.filter(reference => chatMessageRenderableReferenceTypes().has(reference.type))
  const allReferencesFromDocs = isDocset(state?.currentTopic) && renderableReferences.every(isDocReference)

  if (renderableReferences.length === 0) {
    return null
  }

  const title = allReferencesFromDocs
    ? `Search results from ${state.currentTopic!.name}`
    : `${renderableReferences.length} ${renderableReferences.length === 1 ? 'reference' : 'references'}`

  return (
    <Details onToggle={onToggle} className={clsx(className, styles.Details)}>
      <summary className={clsx(styles.referencesContainer)}>
        <span className={styles.title}>{title}</span>
        <Octicon icon={ChevronDownIcon} className="references-chevron-down" />
        <Octicon icon={ChevronUpIcon} sx={{display: 'none !important'}} className="references-chevron-up" />
      </summary>
      <ActionList
        sx={{mt: '12px', mx: '-1rem', p: 1}}
        className={clsx(isImmersive && styles.referencesListImmersiveContainer)}
      >
        {renderableReferences.map(reference => (
          <OutputReference key={referenceID(reference)} reference={reference} />
        ))}
      </ActionList>
    </Details>
  )
}

function isDocReference(reference: CopilotChatReference): boolean {
  return reference.type === 'snippet' && !!reference.languageName && docLanguages.has(reference.languageName)
}

interface ChatMessageReferenceTokensProps {
  references: CopilotChatReference[]
  className?: string
  size: 'small' | 'medium'
  onClickReference?: (e: React.MouseEvent<HTMLAnchorElement>, reference: CopilotChatReference) => void
  align: 'left' | 'right'
}

export function ChatMessageReferenceTokens({
  references,
  className,
  size,
  onClickReference,
  align,
}: ChatMessageReferenceTokensProps) {
  const renderableReferences = references.filter(reference => chatMessageRenderableReferenceTypes().has(reference.type))

  return (
    <Toolbar
      aria-label="Attachments"
      className={clsx(styles.referenceTokensContainer, align === 'right' && styles.alignRight, className)}
    >
      {renderableReferences.map(reference =>
        reference.type === 'figma' && copilotFeatureFlags.immersiveFigmaIntegration ? (
          <FigmaChatReference
            reference={reference}
            key={referenceID(reference)}
            onClick={e => onClickReference?.(e, reference)}
          />
        ) : (
          <ReferenceToken
            reference={reference}
            key={referenceID(reference)}
            size={size}
            onClick={e => onClickReference?.(e, reference)}
          />
        ),
      )}
    </Toolbar>
  )
}
