import {Button} from '@primer/react'
import styles from './RoleAssignmentsTableTab.module.css'
import {clsx} from 'clsx'
import {Link} from '@github-ui/react-core/link'

export interface RoleAssignmentsTableTabProps {
  title: string
  isSelected?: boolean
  count: number
  to: string
}

export function RoleAssignmentsTableTab({title, isSelected = false, count, to, ...rest}: RoleAssignmentsTableTabProps) {
  return (
    <Button
      as={Link}
      variant="invisible"
      aria-current={isSelected ? 'true' : undefined}
      count={count}
      className={clsx(styles.container, isSelected && styles.selected)}
      to={to}
      {...rest}
    >
      <div>{title}</div>
    </Button>
  )
}
