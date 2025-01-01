import {useFragment} from 'react-relay'
import type {DemilestonedEvent$key} from './__generated__/DemilestonedEvent.graphql'
import type {MilestonedEvent$key} from './__generated__/MilestonedEvent.graphql'
import {getWrappedMilestoneLink} from './DemilestonedEvent'
import {MilestonedEventFragment} from './MilestonedEvent'
import {LABELS} from '../constants/labels'

type RolledupMilestonedEventProps = {
  rollupGroup: Record<string, Array<MilestonedEvent$key | DemilestonedEvent$key>>
}

type MilestoneLinkProps = {
  milestoneEventKey: MilestonedEvent$key | DemilestonedEvent$key
  addDelimiter: boolean
}

type WithAttributes<T> = T & {
  // __id is used for the unique key for the element
  __id: string
  // __index is used for sorting the events
  __index: number
  // milestone is used to remove duplicates when it exists
  milestone?: {
    id: string
  }
  // milestoneTitle is used as a fallback for milestone?.id as the milestone may have been deleted
  milestoneTitle: string
}

export function RolledupMilestonedEvent({rollupGroup}: RolledupMilestonedEventProps): JSX.Element {
  const addedEvents = (rollupGroup['MilestonedEvent'] as Array<WithAttributes<MilestonedEvent$key>>) || []
  const removedEvents = (rollupGroup['DemilestonedEvent'] as Array<WithAttributes<DemilestonedEvent$key>>) || []

  const sortedEvents = getSortedEvents(addedEvents, removedEvents)

  const prefix = sortedEvents.length > 1 ? LABELS.timeline.modifiedMilestones : LABELS.timeline.modifiedMilestone

  return (
    <>
      {`${prefix} `}
      {sortedEvents.map((event, index) => (
        <MilestoneLink milestoneEventKey={event} key={event.__id} addDelimiter={index < sortedEvents.length - 1} />
      ))}
    </>
  )
}

// This function is used to sort the events by their index in the timeline and remove duplicates by milestone id (only the first event is kept)
function getSortedEvents(
  addedEvents: Array<WithAttributes<MilestonedEvent$key>>,
  removedEvents: Array<WithAttributes<DemilestonedEvent$key>>,
) {
  const eventOrder: Record<string, number> = {}
  const eventKeys: Record<string, WithAttributes<MilestonedEvent$key> | WithAttributes<DemilestonedEvent$key>> = {}

  const allEvents = [...addedEvents, ...removedEvents]

  for (const event of allEvents) {
    const id = event.milestone?.id || event.milestoneTitle
    const eventIndex = eventOrder[id]
    if (eventIndex === undefined || event.__index < eventIndex) {
      eventOrder[id] = event.__index
      eventKeys[id] = event
    }
  }

  return Object.entries(eventOrder)
    .sort((a, b) => a[1] - b[1])
    .map(([id]) => eventKeys[id])
    .filter(event => event !== undefined)
}

function MilestoneLink({milestoneEventKey, addDelimiter}: MilestoneLinkProps) {
  const data = useFragment(MilestonedEventFragment, milestoneEventKey)

  return getWrappedMilestoneLink(data.milestone?.url, data.milestoneTitle, addDelimiter)
}
