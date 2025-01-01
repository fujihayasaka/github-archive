import {Fragment, useId} from 'react'
import type {ShortcutsGroup} from '../types'
import {KeybindingHint} from '@primer/react/experimental'

import styles from './ShortcutsGroupList.module.css'

interface ShortcutsGroupListProps {
  group: ShortcutsGroup
}

export function ShortcutsGroupList({
  group: {
    service: {name: serviceName},
    commands,
  },
}: ShortcutsGroupListProps) {
  const labelId = useId()

  return (
    <div className={styles.ShortcutsGroupContainer}>
      <h2 id={labelId} className={styles.ShortcutsGroupHeader}>
        {serviceName}
      </h2>
      {/* eslint-disable-next-line jsx-a11y/no-redundant-roles -- listStyleType: 'none' will result in WebKit list semantics so need to explicitly set. */}
      <ul role="list" aria-labelledby={labelId} className={styles.ShortcutsList}>
        {commands.map(({id, name, keybinding}) => (
          <li key={id} className={styles.ShortcutItem}>
            <div>{name}</div>
            <div className={styles.KeybindingContainer}>
              {(Array.isArray(keybinding) ? keybinding : [keybinding]).map((keys, i) => (
                <Fragment key={keys}>
                  {i > 0 && ' or '}
                  <KeybindingHint keys={keys} />
                </Fragment>
              ))}
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
