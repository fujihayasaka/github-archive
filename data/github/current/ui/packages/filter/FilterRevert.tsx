import {testIdProps} from '@github-ui/test-id-props'
import {UndoIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {clsx} from 'clsx'

import styles from './FilterRevert.module.css'

type FilterRevertProps = {
  onClick?: (event: React.SyntheticEvent) => void
  href?: string
  as?: 'a' | 'button'
  className?: string
}

export const FilterRevert = ({className, as, onClick, href}: FilterRevertProps) => {
  return (
    <Link
      {...testIdProps('filter-revert-query')}
      as={as || 'a'}
      href={href}
      onClick={onClick}
      className={clsx(className, styles.Link_0)}
    >
      <UndoIcon className={styles.Octicon_0} />
      Revert filter changes
    </Link>
  )
}
