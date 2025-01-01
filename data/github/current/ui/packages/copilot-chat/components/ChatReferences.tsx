import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {ActionList, Details, Link, useDetails} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import type React from 'react'
import {useMemo} from 'react'

import {getRenderableReferences, isDocset, referenceID} from '../utils/copilot-chat-helpers'
import type {CopilotChatMessage, CopilotChatReference} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState} from '../utils/CopilotChatContext'
import {docLanguages} from '../utils/language-info'
import {OutputReference} from './ChatReference'
import styles from './ChatReferences.module.css'
import {FigmaChatReference} from './FigmaChatReference'
import {ReferenceToken} from './ReferenceToken'
import {Toolbar} from './Toolbar'

export interface ChatMessageReferencesListProps {
  references: CopilotChatReference[]
  onToggle?: (e: React.SyntheticEvent) => void
  isImmersive?: boolean
  className?: string
}

/** renders references for assistant messages */
export function ChatMessageReferencesList({
  references,
  onToggle,
  isImmersive,
  className,
}: ChatMessageReferencesListProps) {
  const state = useChatState() as ReturnType<typeof useChatState> | undefined // if we're run in tests without context, this will be undefined
  const renderableReferences = useMemo(() => getRenderableReferences(references), [references])
  const {getDetailsProps} = useDetails({})
  const allReferencesFromDocs = useMemo(
    () => isDocset(state?.currentTopic) && renderableReferences.every(isDocReference),
    [state?.currentTopic, renderableReferences],
  )
  const webSearchUsed = useMemo(
    () => renderableReferences.some(ref => ref.type === 'web-search-result'),
    [renderableReferences],
  )

  if (renderableReferences.length === 0) {
    return null
  }

  const title =
    allReferencesFromDocs && state?.currentTopic?.name
      ? `Search results from ${state.currentTopic.name}`
      : `${renderableReferences.length} ${renderableReferences.length === 1 ? 'reference' : 'references'}`

  return (
    <Details {...getDetailsProps()} onToggle={onToggle} className={clsx(className, styles.Details)}>
      <summary className={clsx(styles.referencesContainer)}>
        <span className={clsx(styles.title, isImmersive ? '' : styles.assistiveTitle)}>{title}</span>
        <Octicon icon={ChevronDownIcon} className="references-chevron-down" sx={{color: 'fg.muted'}} />
        <Octicon
          icon={ChevronUpIcon}
          sx={{display: 'none !important', color: 'fg.muted'}}
          className="references-chevron-up"
        />
      </summary>
      <ActionList
        sx={{mt: 2, mx: '-1rem', p: 1}}
        className={clsx(isImmersive && styles.referencesListImmersiveContainer)}
      >
        {renderableReferences.map(reference => (
          <OutputReference key={referenceID(reference)} reference={reference} />
        ))}

        {webSearchUsed && (
          <div className={styles.chatMessageReferenceListFooter}>
            Copilot used the{' '}
            <Link
              inline
              href="https://gh.io/azure-ai-agent-with-bing-grounding"
              target="_blank"
              rel="noopener noreferrer"
            >
              Bing Search
            </Link>{' '}
            tool.{' '}
            <Link inline href="https://privacy.microsoft.com/privacystatement" rel="nofollow" target="_blank">
              Microsoft Privacy Statement
            </Link>
          </div>
        )}
      </ActionList>
    </Details>
  )
}

function isDocReference(reference: CopilotChatReference): boolean {
  return reference.type === 'snippet' && !!reference.languageName && docLanguages.has(reference.languageName)
}

export interface ChatMessageReferenceTokensProps {
  references: CopilotChatReference[]
  message?: CopilotChatMessage
  className?: string
  size: 'small' | 'medium'
  onClickReference?: (reference: CopilotChatReference, e?: React.MouseEvent<HTMLAnchorElement>) => void
  getReferenceVersion?: (reference: CopilotChatReference) => number | undefined
}

/** renders references for user messages */
export function ChatMessageReferenceTokens({
  references,
  message,
  className,
  size,
  onClickReference,
  getReferenceVersion,
}: ChatMessageReferenceTokensProps) {
  const {bigReferences, smallReferences} = useMemo(() => partitionReferences(references), [references])
  const renderReference = (reference: CopilotChatReference) =>
    reference.type === 'figma' && copilotFeatureFlags.immersiveFigmaIntegration ? (
      <FigmaChatReference
        reference={reference}
        key={referenceID(reference)}
        onClick={e => onClickReference?.(reference, e)}
      />
    ) : (
      <ReferenceToken
        message={message}
        reference={reference}
        key={referenceID(reference)}
        size={size}
        onClick={(_, e) => onClickReference?.(reference, e)}
        getReferenceVersion={getReferenceVersion}
      />
    )

  return (
    <Toolbar aria-label="Attachments" className={clsx(styles.referenceTokensOuterContainer, className)}>
      {bigReferences.map(renderReference)}
      <div className={styles.referenceTokensContainer}>{smallReferences.map(renderReference)}</div>
    </Toolbar>
  )
}

const BIG_REFERENCE_TYPES = new Set(['figma', 'image'])

/**
 * Filters out unrenderable references and partitions them into bigReferences (rendered on their own line),
 * and smallReferences (rendered inline).
 */
function partitionReferences(references: CopilotChatReference[]) {
  const renderableReferences = getRenderableReferences(references)
  const bigReferences: CopilotChatReference[] = []
  const smallReferences: CopilotChatReference[] = []
  for (const r of renderableReferences) {
    if (BIG_REFERENCE_TYPES.has(r.type)) {
      bigReferences.push(r)
    } else {
      smallReferences.push(r)
    }
  }
  return {bigReferences, smallReferences}
}
