export type ReactionContent =
  | 'CONFUSED'
  | 'EYES'
  | 'HEART'
  | 'HOORAY'
  | 'LAUGH'
  | 'ROCKET'
  | 'THUMBS_DOWN'
  | 'THUMBS_UP'

export const EMOJI_MAP: Record<string, string> = {
  CONFUSED: '😕',
  EYES: '👀',
  HEART: '❤️',
  HOORAY: '🎉',
  LAUGH: '😄',
  THUMBS_DOWN: '👎',
  THUMBS_UP: '👍',
  ROCKET: '🚀',
}

export type Reaction = {
  content: ReactionContent
  viewerHasReacted: boolean
}

export type ReactionViewerGroup = {
  reaction: Reaction
  reactors: Reactor[]
  totalCount: number
}

export type Reactor = {
  typeName: 'Bot' | 'Mannequin' | 'User' | 'Organization' | 'Other'
  login: string
}

export function summarizeReactors(reactors: string[], totalReactedUsers: number): string {
  if (reactors.length === 0 || totalReactedUsers === 0) return ''
  const summary = reactors.slice(0)

  if (summary.length === 1) return summary[0]!
  if (summary.length === 2) return summary.join(' and ')
  if (totalReactedUsers > reactors.length) summary.push(`${totalReactedUsers - reactors.length} more`)

  const last = summary.pop()
  summary.push(`${summary.pop()} and ${last}`)
  return summary.join(', ')
}

export function constructReactionButtonLabel(
  reaction: string,
  reacted: boolean,
  reactors: string[],
  totalReactedUsers: number,
): string {
  if (reactors.length === 0 || totalReactedUsers === 0) {
    return ``
  }
  return `${reacted ? 'React' : 'Unreact'} with ${EMOJI_MAP[reaction]} (${reactors.length} ${
    EMOJI_MAP[reaction]
  } reaction${reactors.length === 1 ? '' : 's'} so far, including ${summarizeReactors(reactors, totalReactedUsers)})`
}
