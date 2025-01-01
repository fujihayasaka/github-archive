import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import styles from './SummaryCardBanner.module.css'

// Banner with styles for use in summary cards
// - removes border-radius and left/right borders of the Banner defaults
// - applies color-fg-muted for the default text color
export function SummaryCardBanner(props: React.ComponentProps<typeof Banner>) {
  const {className, ...rest} = props
  return <Banner {...rest} className={clsx('color-fg-muted', className, styles.summaryCardBanner)} />
}
