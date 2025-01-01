import {type TestIdProps, testIdProps} from '@github-ui/test-id-props'
import {useContainerBreakpoint} from '@github-ui/use-container-breakpoint'
import {Box} from '@primer/react'
import {clsx} from 'clsx'
import {useRef} from 'react'

import styles from './filter-container.module.css'

type FilterContainerProps = {
  className?: string
} & TestIdProps

/**
 * Renders a styled div for the `<Tokenized`FilterInput />` component
 */
export function FilterContainer({children, className, ...props}: React.PropsWithChildren<FilterContainerProps>) {
  const filterContainerRef = useRef<HTMLDivElement>(null)

  const breakpoint = useContainerBreakpoint(filterContainerRef.current)

  return (
    <Box
      ref={filterContainerRef}
      role="region"
      aria-label="View filters"
      {...testIdProps('base-filter-input')}
      sx={{
        flexWrap: breakpoint(['wrap', 'nowrap']),
        justifyContent: breakpoint(['flex-end', 'space-between']),
      }}
      className={clsx(styles.Box, className)}
      {...props}
    >
      {children}
    </Box>
  )
}
