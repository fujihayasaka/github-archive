import {Button, type ButtonBaseProps, IconButton, useResponsiveValue} from '@primer/react'
import {CodeIcon} from '@primer/octicons-react'
import type {Model} from '@github-ui/marketplace-common'
import {sendEvent, type SendEventContext} from '@github-ui/hydro-analytics'
import {useUser} from '@github-ui/use-user'
import {testIdProps} from '@github-ui/test-id-props'
import {GettingStartedButtonClicked} from '../utils/playground-types'

interface UseThisModelButtonProps
  extends Pick<ButtonBaseProps, 'onClick' | 'variant' | 'block' | 'tabIndex' | 'className'> {
  model: Model
  hideLabelOnSmallScreens?: boolean
}

export function UseThisModelButton({hideLabelOnSmallScreens = true, model, ...buttonProps}: UseThisModelButtonProps) {
  const {currentUser} = useUser()
  const onClick = buttonProps.onClick
  const label = 'Use this model'
  const isMobile = useResponsiveValue({narrow: true}, false)

  const commonButtonProps: Omit<ButtonBaseProps, 'aria-label' | 'aria-labelledby'> = {
    ...buttonProps,
    onClick: evt => {
      if (onClick) onClick(evt)
      const payload: SendEventContext = {
        registry: model.registry,
        model: model.name,
        publisher: model.publisher,
        label,
        analyticsTrackingId: currentUser?.analyticsTrackingId,
      }
      sendEvent(GettingStartedButtonClicked, payload)
    },
    ...testIdProps('get-api-key-button'),
  }

  if (!isMobile || !hideLabelOnSmallScreens) {
    return (
      <Button leadingVisual={CodeIcon} {...commonButtonProps}>
        {label}
      </Button>
    )
  }

  return <IconButton {...commonButtonProps} aria-label={label} icon={CodeIcon} />
}
