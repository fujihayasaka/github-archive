import {Toasts} from '@github-ui/toast/Toasts'
import {ToastContextProvider} from '@github-ui/toast/ToastContext'
import type {Decorator} from '@storybook/react'

export const withToasts: Decorator = (Story, context) => {
  return (
    <ToastContextProvider>
      <Toasts />
      {Story(context)}
    </ToastContextProvider>
  )
}
