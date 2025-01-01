import styles from './ControlGroupContainer.module.css'
import {clsx} from 'clsx'

type ControlGroupContainerProps = {
  children: React.ReactNode
  border?: boolean
  fullWidth?: boolean
  ['data-testid']?: string
  className?: string
}

const ControlGroupContainer = ({
  children,
  fullWidth = false,
  border = true,
  'data-testid': testId,
  className,
}: ControlGroupContainerProps) => {
  return (
    <div
      data-testid={testId}
      className={clsx(styles.ControlGroupContainer, fullWidth && styles.fullWidth, border && styles.border, className)}
    >
      {children}
    </div>
  )
}

export default ControlGroupContainer
