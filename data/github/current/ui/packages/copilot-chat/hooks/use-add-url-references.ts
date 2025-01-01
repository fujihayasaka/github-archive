import {useMutation} from '@github-ui/react-query'
import type {SyntheticChangeEmitter} from '@github-ui/use-synthetic-change'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {RefObject} from 'react'

import type {CopilotChatReference, FigmaReference} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import {ReferenceMention} from '../utils/reference-mention'

const figmaUrlPattern = /^(?:https:\/\/)?(?:www\.)?(figma\.com\/.+)$/

class FigmaNotAuthorizedError extends Error {
  constructor() {
    super()
    this.name = 'FigmaNotAuthorizedError'
  }
}

interface ReferenceRequestArgs {
  itemUrl: string
  parsedReferenceMention: ReferenceMention
}

export function useAddUrlReferences({
  figmaAuthUrl,
  textAreaRef,
  emitChange,
}: {
  figmaAuthUrl?: string
  textAreaRef: RefObject<HTMLTextAreaElement | null>
  emitChange: SyntheticChangeEmitter
}) {
  const manager = useChatManager()
  const {currentReferences} = useChatState()

  /**
   * Find and replace all occurrences of `search` in the input with `replace`. If `range` is provided, will limit the
   * updates to just the selected slice of the input. Uses `emitChange` to preserve the undo history of the input in
   * supported browsers.
   */
  const findAndReplace = (search: string, replace: string, range?: [startInclusive: number, endExclusive: number]) => {
    if (!textAreaRef.current || search === replace) return

    const offset = range?.[0] ?? 0

    // If we continually grab the latest value from the input element, the range window could be changing because the
    // length of `replace` may not be equal to the length of `search`. So we work with a 'mirror' string that we extract
    // at the beginning and apply the same changes in both places.
    let valueInRange = textAreaRef.current.value.slice(offset, range?.[1])

    let start = valueInRange.indexOf(search)
    while (start > -1) {
      const end = start + search.length
      emitChange(replace, [start + offset, end + offset])

      valueInRange = valueInRange.replace(search, replace)
      start = valueInRange.indexOf(search)
    }
  }

  // This is probably a misuse of `useMutation`, but it's a decent compromise that allows us to fetch imperatively.
  // It does unfortunately mean that we don't get any caching, since mutations aren't cached.

  const githubReferenceQuery = useMutation({
    mutationFn: async ({itemUrl}: ReferenceRequestArgs) => {
      const response = await verifiedFetchJSON(`/copilot/chat-links?item_url=${itemUrl}`)
      if (!response.ok) throw new Error(`Failed to fetch reference data (${response.status}: ${response.statusText})`)
      return (await response.json()) as CopilotChatReference
    },
    onSuccess: (reference, {parsedReferenceMention}) => {
      manager.addReference(reference, 'chatInput')

      // For files, the reference mention cannot be fully obtained from the URL because the ref name from the URL can
      // contain slashes (ie, `/blob/branchPartA/branchPartB/filePartA/filePartB`). Only the server can determine what
      // parts of the URL are the ref vs the file path, by querying the git repo. So we have to update the mention text
      // based on what the server returns.
      const resolvedReferenceMention = ReferenceMention.for(reference)
      if (!resolvedReferenceMention) return

      const parsedReferenceMentionStr = ReferenceMention.stringify(parsedReferenceMention)
      const resolvedReferenceMentionStr = ReferenceMention.stringify(resolvedReferenceMention)
      if (parsedReferenceMentionStr === resolvedReferenceMentionStr) return

      findAndReplace(parsedReferenceMentionStr, resolvedReferenceMentionStr)
    },
    onError: (_, {itemUrl, parsedReferenceMention}) => {
      // revert back to the URL
      const parsedReferenceMentionStr = ReferenceMention.stringify(parsedReferenceMention)
      findAndReplace(parsedReferenceMentionStr, itemUrl)
    },
  })

  const figmaReferenceQuery = useMutation({
    mutationFn: async (itemUrl: string) => {
      const response = await verifiedFetchJSON(`/copilot/immersive/figma-link?item_url=${itemUrl}`)
      if (!response.ok) {
        if (response.status === 403) throw new FigmaNotAuthorizedError()
        throw new Error(`Failed to fetch Figma reference data (${response.status}: ${response.statusText})`)
      }
      return (await response.json()) as FigmaReference
    },
    onSuccess: reference => manager.addReference(reference, 'chatInput'),
    onError: (error, itemUrl) => {
      // for figma we create this fake reference to give the user a link to initiate oauth with figma
      // would be nice if this could be more general
      if (figmaAuthUrl && error instanceof FigmaNotAuthorizedError)
        manager.addReference(
          {
            type: 'figma',
            title: 'Sign in to Figma',
            id: `forbidden-${itemUrl}`,
            url: figmaAuthUrl,
            thumbnailUrl: '',
            fullImageUrl: '',
            authenticationRequired: true,
          },
          'chatInput',
        )
    },
  })

  /**
   * If the passed text is a valid reference URL, fetches reference details and adds the reference to chat state.
   * @param range Range of text in the input in which to look for a URL. Providing this range prevents unexpectedly
   * updating text outside of where the user pasted.
   */
  const replaceUrlWithReferenceMention = (range: [startInclusive: number, endExclusive: number]) => {
    const text = textAreaRef.current?.value.slice(...range) ?? ''

    // We only do reference processing if the entire pasted text is a single URL
    if (/\s/.test(text)) return text

    const parsedReferenceMention = ReferenceMention.fromUrl(text)
    if (parsedReferenceMention) {
      // Avoid unecessary fetches / loading states
      if (currentReferences.every(ref => !ReferenceMention.refersTo(parsedReferenceMention, ref)))
        githubReferenceQuery.mutate({itemUrl: text, parsedReferenceMention})

      findAndReplace(text, ReferenceMention.stringify(parsedReferenceMention), range)
    }

    const figmaReferenceMatch = figmaUrlPattern.exec(text)
    if (figmaReferenceMatch) {
      figmaReferenceQuery.mutate(text)
      findAndReplace(text, figmaReferenceMatch[1]!, range)
    }

    return text
  }

  return {
    isLoading: githubReferenceQuery.isPending || figmaReferenceQuery.isPending,
    replaceUrlWithReferenceMention,
  }
}
