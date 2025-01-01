import type {IssueTimelineItem$data} from '../components/timeline/__generated__/IssueTimelineItem.graphql'

type ArrayElement<ArrayType extends readonly unknown[]> = ArrayType extends ReadonlyArray<infer ElementType>
  ? ElementType
  : never

type WithIndex<T> = T & {__index: number}
type ArrayWithIndex<T> = Array<WithIndex<T>>

export type TimelineItem = IssueTimelineItem$data | null

const ROLLUP_TIME_CUTOFF = 1000 * 60 * 60 * 24 * 7 // a week - this is in parity with rails

const ENABLED_ROLLUP_TYPE_MAP: Record<string, Set<string>> = {
  LabeledEvent: new Set(['LabeledEvent', 'UnlabeledEvent']),
  UnlabeledEvent: new Set(['LabeledEvent', 'UnlabeledEvent']),
  CrossReferencedEvent: new Set(['CrossReferencedEvent']),
  ReferencedEvent: new Set(['ReferencedEvent']),
  AssignedEvent: new Set(['AssignedEvent', 'UnassignedEvent']),
  UnassignedEvent: new Set(['AssignedEvent', 'UnassignedEvent']),
  AddedToProjectV2Event: new Set(['AddedToProjectV2Event', 'RemovedFromProjectV2Event']),
  RemovedFromProjectV2Event: new Set(['AddedToProjectV2Event', 'RemovedFromProjectV2Event']),
  MilestonedEvent: new Set(['MilestonedEvent', 'DemilestonedEvent']),
  DemilestonedEvent: new Set(['MilestonedEvent', 'DemilestonedEvent']),
  SubIssueAddedEvent: new Set(['SubIssueAddedEvent']),
  SubIssueRemovedEvent: new Set(['SubIssueRemovedEvent']),
}

const getCreatedAt = (event: TimelineItem): Date | undefined => {
  if (event?.__typename && ENABLED_ROLLUP_TYPE_MAP[event.__typename]) {
    return (event.createdAt && new Date(event.createdAt)) || undefined
  }

  return undefined
}

const canPerformSpecificEventRollup = (event: NonNullable<TimelineItem>): boolean => {
  if (event.__typename === 'CrossReferencedEvent' && event.willCloseTarget) {
    return false
  }

  return true
}

const eventCanRollup = <T extends TimelineItem>(event: T, nextEvent: T): boolean => {
  if (!event || !nextEvent || !event.actor) {
    return false
  }

  if (!ENABLED_ROLLUP_TYPE_MAP[event.__typename]?.has(nextEvent.__typename)) {
    return false
  }

  if (event.actor?.login !== nextEvent.actor?.login) {
    return false
  }

  if (!canPerformSpecificEventRollup(event) || !canPerformSpecificEventRollup(nextEvent)) {
    return false
  }

  const createdAt = getCreatedAt(event)
  const nextCreatedAt = getCreatedAt(nextEvent)

  if (
    createdAt === undefined ||
    nextCreatedAt === undefined ||
    Math.abs(createdAt.getTime() - nextCreatedAt.getTime()) > ROLLUP_TIME_CUTOFF
  ) {
    return false
  }
  return true
}

const totalRolledUpEvents = <T>(rollups: Record<string, T[]>): number => {
  let total = 0
  for (const key in rollups) {
    total += rollups[key]!.length
  }

  return total
}

export interface RolledUpTimelineItem<T extends TimelineItem> {
  item: T | null
  rollupGroup: Record<string, ArrayWithIndex<T>> | undefined
}

export const rollupEvents = <T extends TimelineItem>(events: T[]): Array<RolledUpTimelineItem<T>> => {
  const rolledUpEvents: Array<RolledUpTimelineItem<T>> = []
  let index = 0
  while (index < events.length) {
    const rollups = rollupCurrentEvent(events, index)

    // This includes the current event
    const totalEventsRolledUp = totalRolledUpEvents(rollups)
    const currentEvent = events[index]

    if (rollups) removeDuplicateRollupEvents(rollups)

    rolledUpEvents.push({
      item: currentEvent ?? null,
      rollupGroup: totalEventsRolledUp > 1 ? rollups : undefined,
    })

    // For null/undefined events the rollups will be empty but we need to increment at least 1.
    index += Math.max(totalEventsRolledUp, 1)
  }

  return rolledUpEvents
}

const rollupCurrentEvent = <T extends TimelineItem>(events: T[], index: number): Record<string, ArrayWithIndex<T>> => {
  let currentEvent = events[index]!
  const rollups = [currentEvent]

  while (index + 1 < events.length) {
    const nextEvent = events[index + 1]!
    if (!eventCanRollup(currentEvent, nextEvent)) {
      break
    }

    currentEvent = nextEvent
    rollups.push(currentEvent)
    index++
  }

  return partitionRollups(rollups)
}

const partitionRollups = <T extends TimelineItem>(rollups: T[]): Record<string, ArrayWithIndex<T>> => {
  // Partition the distinct rolled up groups by __typename
  const distinctRollups: Record<string, ArrayWithIndex<T>> = {}
  let index = 0
  for (const rollup of rollups) {
    if (!rollup) {
      continue
    }

    const key = rollup.__typename
    if (!distinctRollups[key]) {
      distinctRollups[key] = []
    }

    // Add the index to the rollup so we can sort them later by their position in the timeline
    distinctRollups[key].push({__index: index, ...rollup})
    index++
  }

  return distinctRollups
}

const removeDuplicateRollupEvents = (rollups: Record<string, TimelineItem[]>) => {
  for (const value of Object.values(rollups)) {
    const uniqueIds = new Set()

    for (let i = 0; i < value.length; i++) {
      const event = value[i]
      if (!event) {
        continue
      }
      const {__typename: eventName} = event || {}
      const id = getEventItemId(event)

      if (id) {
        const uniqueKey = `${id}-${eventName}`
        if (uniqueIds.has(uniqueKey)) {
          value.splice(i--, 1) // Remove duplicate and adjust index
        } else {
          uniqueIds.add(uniqueKey)
        }
      }
    }
  }
}

const getEventItemId = (item: TimelineItem): string | undefined => {
  const type = item?.__typename

  switch (type) {
    case 'LabeledEvent':
    case 'UnlabeledEvent':
      return item?.label?.id
    case 'AssignedEvent':
    case 'UnassignedEvent':
      /*
        %other is generated by relay as a fallback for union types i.e type of assignee in this case.
        It doesn't contain any field properties hence the need for the extra check
      */
      return item?.assignee?.__typename !== '%other' ? item?.assignee?.id : undefined
    default:
      return undefined
  }
}
