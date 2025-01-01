import type {FC} from 'react'
import type {BypassActor} from '../../bypass-actors-types'
import {BypassListRow} from './BypassListRow'

export type BypassListProps = {
  readOnly?: boolean
  isBypassModeEnabled: boolean
  removeBypassActor: (bypassActor: BypassActor) => void
  refocusOnRemoval?: () => void
  updateBypassActor: (bypassActor: BypassActor) => void
  enabledBypassActors: BypassActor[]
  baseAvatarUrl: string
}

export const BypassList: FC<BypassListProps> = ({
  readOnly,
  isBypassModeEnabled,
  removeBypassActor,
  refocusOnRemoval,
  updateBypassActor,
  enabledBypassActors,
  baseAvatarUrl,
}: BypassListProps) => {
  return (
    <>
      {enabledBypassActors.map(actor => (
        <BypassListRow
          key={`${actor.actorType}-${actor.id || actor._id}`}
          actor={actor}
          baseAvatarUrl={baseAvatarUrl}
          readOnly={readOnly}
          removeBypassActor={removeBypassActor}
          refocusOnRemoval={refocusOnRemoval}
          updateBypassActor={updateBypassActor}
          isBypassModeEnabled={isBypassModeEnabled}
        />
      ))}
    </>
  )
}
