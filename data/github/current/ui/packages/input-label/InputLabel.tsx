import {Text, type SxProp} from '@primer/react'
import type React from 'react'
import styles from './InputLabel.module.css'
import {clsx} from 'clsx'

type BaseProps = SxProp & {
  disabled?: boolean
  required?: boolean
  visuallyHidden?: boolean
  id?: string
  className?: string
  children?: React.ReactNode
}

export type LabelProps = BaseProps & {
  htmlFor?: string
  as?: 'label'
}

export type LegendOrSpanProps = BaseProps & {
  as: 'legend' | 'span'
  htmlFor?: undefined
}

export type InputLabelProps = LabelProps | LegendOrSpanProps

/**
 * Primer-styled input label for forms; can also be rendered as a fieldset `legend`.
 * Copied from `primer/react/src/internal/components/InputLabel.tsx`.
 */
const InputLabel = ({
  children,
  disabled,
  required,
  visuallyHidden,
  sx,
  as = 'label',
  className,
  ...props
}: InputLabelProps) => {
  return (
    <Text
      as={as as unknown as undefined}
      sx={{
        color: disabled ? 'fg.muted' : 'fg.default',
        cursor: disabled ? 'not-allowed' : 'pointer',
        ...sx,
      }}
      className={clsx(visuallyHidden ? clsx('sr-only', className) : className, styles.Text)}
      {...props}
    >
      {required ? (
        <span className={styles.Box}>
          <div className={styles.Box_1}>{children}</div>
          <span>*</span>
        </span>
      ) : (
        children
      )}
    </Text>
  )
}

export default InputLabel
