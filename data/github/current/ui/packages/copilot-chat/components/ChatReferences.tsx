import {ChevronDownIcon, ChevronUpIcon} from '@primer/octicons-react'
import {ActionList, Box, Details, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import type React from 'react'

import {isDocset, referenceID} from '../utils/copilot-chat-helpers'
import type {CopilotChatReference} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {docLanguages} from '../utils/language-info'
import {OutputReference} from './ChatReference'

export const RENDERABLE_REFERENCE_TYPES = [
  'file',
  'file-diff',
  'snippet',
  'symbol',
  'commit',
  'pull-request',
  'third-party',
  'repo-instructions',
]

export interface ChatReferencesProps {
  references: CopilotChatReference[]
  onToggle?: (e: React.SyntheticEvent) => void
  summaryRef?: React.RefObject<HTMLElement>
}

export function ChatReferences({references, onToggle, summaryRef}: ChatReferencesProps) {
  const state = useChatState() as ReturnType<typeof useChatState> | undefined // if we're run in tests without context, this will be undefined
  const renderableReferences = references.filter(reference => RENDERABLE_REFERENCE_TYPES.includes(reference.type))
  const allReferencesFromDocs = isDocset(state?.currentTopic) && renderableReferences.every(isDocReference)

  if (renderableReferences.length === 0) {
    return null
  }

  const title = allReferencesFromDocs
    ? `Search results from ${state.currentTopic!.name}`
    : `${renderableReferences.length} ${renderableReferences.length === 1 ? 'reference' : 'references'}`

  return (
    <Details
      sx={{
        '&[open]': {
          '.references-chevron-down': {
            display: 'none !important',
          },
          '.references-chevron-up': {
            display: 'inline-block !important',
          },
        },
      }}
      onToggle={onToggle}
    >
      <Box
        ref={summaryRef}
        as="summary"
        sx={{
          display: 'flex',
          justifyContent: 'start',
          alignItems: 'center',
          gap: 1,
          mt: 2,
          color: 'fg.muted',
          '&:hover': {
            color: 'fg.default',
          },
        }}
      >
        <Text sx={{fontWeight: 'normal', fontSize: 0}}>{title}</Text>
        <Octicon icon={ChevronDownIcon} className="references-chevron-down" />
        <Octicon icon={ChevronUpIcon} sx={{display: 'none !important'}} className="references-chevron-up" />
      </Box>
      <ActionList sx={{mt: 2, mx: '-1rem', p: 0}}>
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
