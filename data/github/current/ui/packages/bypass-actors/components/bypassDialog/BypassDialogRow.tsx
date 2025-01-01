import {Fragment} from 'react'
import {Checkbox, FormControl, Truncate} from '@primer/react'
import type {BypassActor, BypassActorType} from '../../bypass-actors-types'
import {ActorBypassMode} from '../../bypass-actors-types'
import {BypassAvatar} from '../BypassAvatar'
import {ActorType} from '../ActorType'
import {alreadyAdded} from './alreadyAdded'

import styles from './BypassDialogRow.module.css'
import {clsx} from 'clsx'

type BypassDialogRowProps = {
  actorId: number | string | null
  actorType: BypassActorType
  name: string
  owner?: string
  selected: BypassActor[]
  setSelected: (selected: BypassActor[]) => void
  baseAvatarUrl: string
  enabledBypassActors: BypassActor[]
}

export function BypassDialogRow({
  actorId,
  actorType,
  name,
  owner,
  selected,
  setSelected,
  baseAvatarUrl,
  enabledBypassActors,
}: BypassDialogRowProps) {
  const isChecked = selected.some(item => item.actorId === actorId && item.actorType === actorType)
  return (
    <FormControl>
      <Checkbox
        data-testid="bypass-dialog-checkbox"
        value="actorId"
        checked={isChecked || alreadyAdded(actorId, actorType, enabledBypassActors)}
        onChange={() => {
          if (isChecked) {
            const index = selected.findIndex(
              bypassActor => bypassActor?.actorId === actorId && bypassActor?.actorType === actorType,
            )
            if (index > -1) setSelected([...selected.slice(0, index), ...selected.slice(index + 1)])
          } else {
            setSelected([
              ...selected,
              {actorId, actorType, name, _enabled: true, _dirty: true, bypassMode: ActorBypassMode.ALWAYS, owner},
            ])
          }
        }}
      />
      <FormControl.LeadingVisual>
        <BypassAvatar baseUrl={baseAvatarUrl} id={actorId} name={name} type={actorType} />
      </FormControl.LeadingVisual>
      <FormControl.Label>
        <div className={styles.Box}>
          <Truncate title={name} maxWidth={250}>
            <span className={styles.Text}>{name}</span>
          </Truncate>
          <ActorType actorType={actorType} />
          {actorType === 'Team' ? (
            <Fragment>
              <span className={clsx('note', styles.Text_1)}>&bull;</span>
              <Truncate title={`@${name}`} maxWidth={250}>
                <span className={clsx('note', styles.Text)}>{`@${name}`}</span>
              </Truncate>
            </Fragment>
          ) : null}
          {actorType === 'Integration' && owner ? (
            <Fragment>
              <span className={clsx('note', styles.Text_1)}>&bull;</span>
              <Truncate title={owner} maxWidth={250}>
                <span className={clsx('note', styles.Text)}>{owner}</span>
              </Truncate>
            </Fragment>
          ) : null}
        </div>
      </FormControl.Label>
    </FormControl>
  )
}
