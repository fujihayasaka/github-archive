import {Text} from '@primer/react'
import {clsx} from 'clsx'

import styles from './shared.module.css'

type SelectorLabelProps = Omit<React.ComponentProps<typeof Text>, 'sx'> & {
  className?: string
}

export const SelectorLabel = ({children, className, ...props}: SelectorLabelProps) => (
  <Text className={clsx(styles.Text, className)} {...props}>
    {children}
  </Text>
)
