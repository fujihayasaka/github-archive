import type {Icon} from '@primer/octicons-react'
import {Box, type BoxProps} from '@primer/react'
import type {PropsWithChildren, ReactNode} from 'react'

import {BlankslateErrorMessage} from '../../../../components/error-boundaries/blankslate-error-message'
import styles from './base-chart-error.module.css'

interface MissingChartErrorProps extends Omit<BoxProps, 'content'> {
  icon?: Icon
  heading: ReactNode
  content: ReactNode
}

export const BaseChartError: React.FC<PropsWithChildren<MissingChartErrorProps>> = ({
  icon,
  heading,
  content,
  children,
  ...props
}) => {
  return (
    <Box className={styles.Box} {...props}>
      <BlankslateErrorMessage icon={icon} heading={heading} content={content}>
        {children}
      </BlankslateErrorMessage>
    </Box>
  )
}
