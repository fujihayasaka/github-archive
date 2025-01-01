import {CheckboxGroup} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import type {BypassActor} from '../../bypass-actors-types'
import {BypassDialogRow} from './BypassDialogRow'
import {alreadyAdded} from './alreadyAdded'

import styles from './BypassDialogBody.module.css'

type DialogBodyProps = {
  suggestions: BypassActor[]
  selected: BypassActor[]
  setSelected: (selected: BypassActor[]) => void
  baseAvatarUrl: string
  enabledBypassActors: BypassActor[]
}

export function BypassDialogBody({
  suggestions,
  selected,
  setSelected,
  baseAvatarUrl,
  enabledBypassActors,
}: DialogBodyProps) {
  const newSuggestions = suggestions.filter(s => !alreadyAdded(s.actorId, s.actorType, enabledBypassActors))
  return (
    <div className={styles.Box}>
      {newSuggestions.length > 0 ? (
        <CheckboxGroup aria-labelledby="suggestionsHeading" className={styles.CheckboxGroup}>
          <ul className="list-style-none">
            {newSuggestions.map(s => {
              return (
                <li key={`${s.actorId}-${s.actorType}`}>
                  <BypassDialogRow
                    actorId={s.actorId}
                    actorType={s.actorType}
                    name={s.name}
                    owner={s.owner}
                    selected={selected}
                    setSelected={setSelected}
                    baseAvatarUrl={baseAvatarUrl}
                    enabledBypassActors={enabledBypassActors}
                  />
                </li>
              )
            })}
          </ul>
        </CheckboxGroup>
      ) : (
        <div className={styles.Box_1}>
          <div className={styles.Box_2}>
            <Blankslate>
              <Blankslate.Heading as="h3">No suggestions</Blankslate.Heading>
            </Blankslate>
          </div>
        </div>
      )}
    </div>
  )
}
