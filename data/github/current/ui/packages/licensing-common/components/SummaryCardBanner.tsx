import {Banner} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {forwardRef} from 'react'
import styles from './SummaryCardBanner.module.css'

// Banner with styles for use in summary cards
// - removes border-radius and left/right borders of the Banner defaults
// - applies color-fg-muted for the default text color
// - handles ref forwarding (for, e.g., scenarios where we want to focus the banner)
export const SummaryCardBanner = forwardRef<HTMLDivElement, React.ComponentProps<typeof Banner>>(
  function SummaryCardBanner(props, ref) {
    const {className, ...rest} = props
    return <Banner ref={ref} {...rest} className={clsx('color-fg-muted', className, styles.summaryCardBanner)} />
  },
)
