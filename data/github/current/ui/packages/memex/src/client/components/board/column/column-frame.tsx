import {testIdProps} from '@github-ui/test-id-props'
import {Box, type SxProp} from '@primer/react'
import {clsx} from 'clsx'
import {type ComponentPropsWithoutRef, forwardRef, memo} from 'react'

import styles from './column-frame.module.css'

type Props = {
  /**
   * A React node that will be rendered in the header area of the column
   */
  headerContent: React.ReactNode
  id?: string
  onPointerLeave?: React.MouseEventHandler<HTMLElement>
  onClick?: React.MouseEventHandler<HTMLElement>

  /**
   * A name attached to the column for testing, via a data prop
   */
  testingName?: string
} & SxProp

export const COLUMN_WIDTH = 350
export const COLUMN_GAP = 8

export const ColumnFrame = memo(
  forwardRef<HTMLDivElement, React.PropsWithChildren<ComponentPropsWithoutRef<'div'> & Props>>(
    ({headerContent, testingName, children, sx, className, ...rest}, ref) => {
      return (
        <Box
          {...rest}
          sx={sx}
          ref={ref}
          data-board-column={testingName}
          className={clsx(styles.Box, className)}
          {...testIdProps('board-view-column')}
        >
          <div className={styles.Box_1}>{headerContent}</div>
          {children}
        </Box>
      )
    },
  ),
)

ColumnFrame.displayName = 'ColumnFrame'
