import {PencilIcon} from '@primer/octicons-react'
import {ToggleSwitch as PrimerToggleSwitch, IconButton, Button as PrimerButton} from '@primer/react'

import styles from './Controls.module.css'
import {clsx} from 'clsx'

/* --------------
  Custom Control: Allow consumers to add their own custom controls to the ControlGroup
----------------*/

type CustomProps = {
  children: React.ReactNode
}

export const Custom = ({children}: CustomProps) => {
  return <>{children}</>
}
Custom.displayName = 'ControlGroup.Custom'

/* --------------
      Toggle
----------------*/

type ToggleSwitchProps = React.ComponentProps<typeof PrimerToggleSwitch>

export const ToggleSwitch = (props: ToggleSwitchProps) => {
  return <PrimerToggleSwitch size="small" {...props} />
}

ToggleSwitch.displayName = 'ControlGroup.ToggleSwitch'

/* --------------
      Button
----------------*/

type ButtonProps = React.ComponentProps<typeof PrimerButton>

export const Button = (props: ButtonProps) => {
  return <PrimerButton {...props}>{props.children}</PrimerButton>
}

Button.displayName = 'ControlGroup.Button'

/* --------------
    Inline Edit
----------------*/

type InlineEditProps = {
  value?: string | null
}

type IconButtonProps = React.ComponentProps<typeof IconButton>
type OmittedIconButtonProps = Omit<IconButtonProps, 'icon' | 'aria-labelledby' | 'value'>

export const InlineEdit = ({value = null, ...props}: InlineEditProps & OmittedIconButtonProps) => {
  return (
    <div className={clsx('inlineEdit', styles.Box)}>
      <span>{value}</span>
      {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
      <IconButton unsafeDisableTooltip icon={PencilIcon} aria-label="Edit" className={styles.IconButton} {...props} />
    </div>
  )
}

InlineEdit.displayName = 'ControlGroup.InlineEdit'
