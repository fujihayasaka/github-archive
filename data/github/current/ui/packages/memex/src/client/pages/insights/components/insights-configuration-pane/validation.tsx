// Reimplementation of Primer's _InputValidation component
// (used by FormControl.Validation https://primer.style/react/FormControl#with-validation)
// to enable validation messaging for DropdownMenus, which is
// not natively supported (https://primer.style/react/FormControl#formcontrol)

import {AlertFillIcon, CheckCircleFillIcon, type IconProps} from '@primer/octicons-react'
import {clsx} from 'clsx'
import type {ComponentType, PropsWithChildren} from 'react'

import styles from './validation.module.css'

type Props = {
  validationStatus?: 'success' | 'warning' | 'error'
}

const validationIconMap: Record<
  NonNullable<Props['validationStatus']>,
  ComponentType<React.PropsWithChildren<IconProps>>
> = {
  success: CheckCircleFillIcon,
  error: AlertFillIcon,
  warning: AlertFillIcon,
}

export const Validation: React.FC<PropsWithChildren<Props>> = ({children, validationStatus}) => {
  const IconComponent = validationStatus ? validationIconMap[validationStatus] : undefined

  return (
    <span className={clsx(styles.Text, validationStatus && styles[validationStatus])}>
      {IconComponent && (
        <span className={styles.Box}>
          <IconComponent size={12} fill="currentColor" />
        </span>
      )}
      <span>{children}</span>
    </span>
  )
}
