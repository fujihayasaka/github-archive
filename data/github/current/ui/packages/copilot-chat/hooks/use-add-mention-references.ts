import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {unified} from 'unified'
import {visit} from 'unist-util-visit'

import type {CopilotChatReference} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import type {ReferenceType} from '../utils/reference-mention'
import {ReferenceMention} from '../utils/reference-mention'
import {userMessageParser} from '../utils/user-message/user-message-parser'

const getTypeParam = (itemRefType: Exclude<ReferenceType, 'repository'>): string => {
  switch (itemRefType) {
    case 'issue':
      return 'issue'
    case 'pull-request':
      return 'pull_request'
    case 'discussion':
      return 'discussion'
    case 'thread-scoped-file':
    case 'file':
      return 'file'
  }
}

/** Maximum number of references to handle when calling `addReferencesForMentions`. */
const MAX_REFERENCES_TO_ADD = 20

export function useAddMentionReferences() {
  const manager = useChatManager()
  const {currentReferences} = useChatState()

  // This is probably a misuse of `useMutation`, but it's a decent compromise that allows us to fetch imperatively.
  // It does unfortunately mean that we don't get any caching, since mutations aren't cached.

  const mentionReferencesQuery = useMutation({
    mutationFn: async (mention: ReferenceMention) => {
      const pathParams =
        mention.type === 'repository' ? [mention.repo] : [mention.repo, getTypeParam(mention.type), mention.id ?? '']
      const response = await verifiedFetchJSON(`/copilot/chat/reference/${pathParams.join('/')}`)
      if (!response.ok) throw new Error(`Failed to fetch reference data (${response.status}: ${response.statusText})`)
      return (await response.json()) as CopilotChatReference
    },
    onSuccess: reference => manager.addReference(reference, 'chatInput'),
  })

  const addReferenceForMention = (mention: ReferenceMention) => {
    // Skip requests for already-added references
    if (currentReferences.every(reference => !ReferenceMention.refersTo(mention, reference)))
      mentionReferencesQuery.mutate(mention)
  }

  /** Parse the entire chunk of text for all potential reference mentions, then add any that are not present in the current references. */
  const addReferencesForMentions = (text: string) => {
    const messageTree = unified().use(userMessageParser, {references: currentReferences, agents: []}).parse(text)
    let count = 0
    visit(messageTree, node => {
      if (
        node.type === 'reference-mention' &&
        node.data.mentionedReferenceId === undefined &&
        count < MAX_REFERENCES_TO_ADD
      ) {
        count++
        addReferenceForMention(node.data.referenceMention)
      }
    })
  }

  return {
    isLoading: mentionReferencesQuery.isPending,
    addReferenceForMention,
    addReferencesForMentions,
  }
}
