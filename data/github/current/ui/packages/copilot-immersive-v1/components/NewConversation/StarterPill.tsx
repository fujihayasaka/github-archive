import {Icon} from '@github-ui/pacer/Icon'
import {TriangleDownIcon} from '@primer/octicons-react'
import React from 'react'

import styles from './StarterPill.module.css'

type StarterPillProps = {
  name: string
  icon: string
  color: string
  onClick: () => void
  dropdown?: boolean
}

export const StarterPill = React.forwardRef<HTMLButtonElement, StarterPillProps>(
  ({name, icon, color, onClick, dropdown}, ref) => {
    return (
      <button ref={ref} className={styles.container} onClick={onClick}>
        {Icon && (
          <div className={styles.icon}>
            <Icon icon={icon} color={color} />
          </div>
        )}
        <div className={styles.title}>
          {name}
          {dropdown && (
            <div className={styles.dropdown}>
              <TriangleDownIcon />
            </div>
          )}
        </div>
      </button>
    )
  },
)

StarterPill.displayName = 'StarterPill'
