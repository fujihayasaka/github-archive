/**
 * The HeaderButton and HeaderLinkButton are reusable components for rendering
 * the current app listings call to action with some default styling and behaviour
 * to the buttons and links used in the header of the app.
 */

import {Button, LinkButton, useResponsiveValue} from '@primer/react'
import type {PlanInfo} from '../../types'
import checkCanInstall from '../../utilities/check-can-install'
import type {ComponentProps} from 'react'

export type HeaderButtonBaseProps = {
  planInfo: PlanInfo
}

type HeaderButtonProps = HeaderButtonBaseProps & ComponentProps<typeof Button>

export function useHeaderButtonState(planInfo: PlanInfo, props: {disabled?: boolean}) {
  const isMobile = useResponsiveValue({narrow: true}, false) as boolean
  const disabled = Boolean(!checkCanInstall(planInfo).canInstall || props.disabled)

  return {
    disabled,
    'aria-describedby': disabled ? 'install-unavailable-reason' : undefined,
    size: isMobile ? 'medium' : 'large',
  } as const
}

export function HeaderButton({planInfo, ...buttonProps}: HeaderButtonProps) {
  // use the spread for state to get the described by
  const {disabled, size, ...state} = useHeaderButtonState(planInfo, buttonProps)

  return (
    <Button
      as="button"
      variant="primary"
      className={`width-full ${buttonProps.className ? buttonProps.className : ''}`}
      aria-disabled={disabled}
      aria-describedby={state['aria-describedby']}
      size={size}
      {...buttonProps}
      // dont allow disabled prop override since we may want to disable regardless of prop
      disabled={disabled}
    />
  )
}

type HeaderLinkButtonProps = HeaderButtonBaseProps & ComponentProps<typeof LinkButton>

export function HeaderLinkButton({planInfo, ...linkButtonProps}: HeaderLinkButtonProps) {
  // use the spread for state to get the described by
  const {disabled, size, ...state} = useHeaderButtonState(planInfo, linkButtonProps)

  return (
    <LinkButton
      as="a"
      variant="primary"
      className={`width-full ${linkButtonProps.className ? linkButtonProps.className : ''}`}
      aria-describedby={state['aria-describedby']}
      size={size}
      data-testid="header-link-button"
      {...linkButtonProps}
      // dont allow disabled prop override since we may want to disable regardless of prop
      disabled={disabled}
    />
  )
}
