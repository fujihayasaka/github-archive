import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'

import type {CopilotChatReference} from './copilot-chat-types'

const referenceMentionPattern = /^@(?<repo>[\w-.]+\/[\w-.]+)(?:\/(?<type>\w+)\/(?<id>.+))?$/
// Matches thread-scoped file mentions e.g. @filename
// Similar to agentMentionPattern but won't be confused with agents as it comes after agent matcher in userMessageParser
const threadScopedFileMentionPattern = /^@(?<id>[a-zA-Z0-9_.-]+)$/

export type ReferenceType = 'issue' | 'pull-request' | 'discussion' | 'repository' | 'file' | 'thread-scoped-file'

const ReferenceType = {
  /** From the type param in a repository item URL. */
  fromUrlType(urlType: string | undefined) {
    switch (urlType) {
      case 'issues':
        return 'issue'
      case 'pull':
        return 'pull-request'
      case 'discussions':
        return 'discussion'
      case 'blob':
      case 'tree':
        return 'file'
      case undefined:
        return 'repository'
    }
  },
  /** From the type part of the reference mention text. */
  fromMentionType(mentionType: string | undefined) {
    switch (mentionType) {
      case 'issues':
        return 'issue'
      case 'pull':
        return 'pull-request'
      case 'discussions':
        return 'discussion'
      case 'files':
        return 'file'
      case undefined:
        return 'repository'
    }
  },
}

export interface ReferenceMention {
  readonly repo: string
  readonly type: ReferenceType
  readonly id?: string
}

export const ReferenceMention = {
  /**
   * Build the `@mention` syntax for the reference that corresponds to the URL. If the URL does not point to a
   * mentionable reference, returns `undefined`.
   */
  fromUrl(url: string): ReferenceMention | undefined {
    let parsed
    try {
      // If I set `window.location.origin` as the `base` like our ESLint config wants me to, the URL parsing will
      // always succeed. But I only want it to succeed for valid whole URLs.
      // eslint-disable-next-line no-restricted-syntax
      parsed = new URL(url)
    } catch {
      return
    }

    if (parsed.hostname !== window.location.hostname) return

    const [, owner, repo, type, ...rest] = parsed.pathname.split('/')

    const id = rest.join('/')

    const referenceType = ReferenceType.fromUrlType(type)
    if (!owner || !repo || !referenceType) return

    return {
      repo: `${owner}/${repo}`,
      // type is always repo if there's no ID (it could be an index page, for example)
      type: id ? referenceType : 'repository',
      id,
    }
  },
  stringify(mention: ReferenceMention) {
    switch (mention.type) {
      case 'issue':
        return `@${mention.repo}/issues/${mention.id ?? ''}`
      case 'pull-request':
        return `@${mention.repo}/pull/${mention.id ?? ''}`
      case 'discussion':
        return `@${mention.repo}/discussions/${mention.id ?? ''}`
      case 'repository':
        return `@${mention.repo}`
      case 'file':
        return `@${mention.repo}/files/${mention.id ?? ''}`
      case 'thread-scoped-file':
        return `@${mention.id ?? ''}`
    }
  },
  parse(mention: string): ReferenceMention | undefined {
    const match = referenceMentionPattern.exec(mention)?.groups
    if (!match) {
      if (copilotFeatureFlags.pasteTextFiles) {
        const fileMatch = threadScopedFileMentionPattern.exec(mention)?.groups
        if (fileMatch) {
          return {repo: '', type: 'thread-scoped-file', id: fileMatch.id}
        }
      }
      return undefined
    }

    const type = ReferenceType.fromMentionType(match.type)

    return type ? {repo: match.repo!, type, id: match.id} : undefined
  },
  isEqual(a: ReferenceMention, b: ReferenceMention) {
    return ReferenceMention.stringify(a) === ReferenceMention.stringify(b)
  },
  refersTo(mention: ReferenceMention, reference: CopilotChatReference) {
    const mentionForReference = ReferenceMention.for(reference)
    return mentionForReference !== null && ReferenceMention.isEqual(mention, mentionForReference)
  },
  /**
   * Get the `ReferenceMention` for a given reference (or `null` if this reference isn't mentionable). Also adds on a
   * `reference` field that is the same as the passed reference but has a matching TypeScript type for convenience.
   */
  for: (reference: CopilotChatReference) => {
    switch (reference.type) {
      case 'repository':
        return {
          type: 'repository',
          repo: `${reference.ownerLogin}/${reference.name}`,
          reference,
        } as const
      case 'issue':
        return {
          type: 'issue',
          repo: `${reference.repository.owner}/${reference.repository.name}`,
          id: reference.number.toString(),
          reference,
        } as const
      case 'pull-request':
        return {
          type: 'pull-request',
          repo: `${reference.repository.ownerLogin}/${reference.repository.name}`,
          id: reference.number.toString(),
          reference,
        } as const
      case 'discussion':
        return {
          type: 'discussion',
          repo: `${reference.repository.owner}/${reference.repository.name}`,
          id: reference.number.toString(),
          reference,
        } as const
      case 'file':
      case 'folder':
        return {
          type: 'file',
          repo: `${reference.repoOwner}/${reference.repoName}`,
          id: reference.path,
          reference,
        } as const
      case 'thread-scoped-file':
        return {
          type: 'thread-scoped-file',
          repo: '', // thread-scoped files do not have repo
          id: reference.name,
          reference,
        } as const
      default:
        return null
    }
  },
}
