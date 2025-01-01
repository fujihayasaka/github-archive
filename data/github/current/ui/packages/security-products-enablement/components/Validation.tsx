// Reimplementation of Primer's _InputValidation component
// (used by FormControl.Validation https://primer.style/react/FormControl#with-validation)
// to enable validation messaging for DropdownMenus, which is
// not natively supported (https://primer.style/react/FormControl#formcontrol)
//
// Lovingly copied from ui/packages/memex/src/client/pages/insights/components/insights-configuration-pane/validation.tsx
// because I don't want to risk relying on another team's component, but this really should be standardized IMO!

import type React from 'react'
import {AlertFillIcon, CheckCircleFillIcon, type IconProps} from '@primer/octicons-react'
import {Text, type SxProp} from '@primer/react'

import styles from './Validation.module.css'

type ValidationStatus = 'success' | 'warning' | 'error'

interface ValidationProps extends SxProp {
  validationStatus?: ValidationStatus
  children?: React.ReactNode
}

const validationIconMap: Record<ValidationStatus, React.ComponentType<IconProps>> = {
  success: CheckCircleFillIcon,
  error: AlertFillIcon,
  warning: AlertFillIcon,
}

const validationColorMap: Record<ValidationStatus, string> = {
  success: 'success.fg',
  error: 'danger.fg',
  warning: 'attention.fg',
}

const Validation: React.FC<ValidationProps> = ({children, validationStatus, sx}) => {
  const IconComponent = validationStatus ? validationIconMap[validationStatus] : undefined
  const fgColor = validationStatus ? validationColorMap[validationStatus] : undefined

  return (
    <Text
      sx={{
        color: fgColor,
        ...sx,
      }}
      className={styles.Text}
    >
      {IconComponent && (
        <span className={styles.Box}>
          <IconComponent size={12} fill="currentColor" />
        </span>
      )}
      <span>{children}</span>
    </Text>
  )
}

export default Validation
