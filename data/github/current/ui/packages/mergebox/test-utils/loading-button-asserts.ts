import {waitFor} from '@testing-library/react'

// Note: These test helpers are used to verify the loading state of a button.

// Primer handles the loading state when we pass the `loading` prop to the Button component.
// These helpers are used to verify that the button is in the correct state when the `loading` prop is passed.

// The `toHaveAccessibleDescription` matcher is used to verify that the button has the correct loading text.
// That text isnt displayed on the button itself, but is used as the description for the button during the loading state.
// Screen readers will read this text when the button is focused. When not in the loading state, the button should not have an accessible description.

// `aria-disabled` is set to `true` when the button is in a loading state. We can assert some other
// properties of the button to verify that it is in the correct state, but this should cover our bases.

export function assertButtonEnabled(element: HTMLElement) {
  expect(element).toBeInTheDocument()
  expect(element).not.toHaveAccessibleDescription()
  expect(element).not.toHaveAttribute('aria-disabled')
}

export function assertButtonInLoadingState(element: HTMLElement, loadingText: string) {
  expect(element).toBeInTheDocument()
  expect(element).toHaveAccessibleDescription(loadingText)
  expect(element).toHaveAttribute('aria-disabled', 'true')
}

// sometimes the we need to wait for the component to settle
export async function assertWaitForButtonToBeEnabled(element: HTMLElement) {
  await waitFor(() => {
    expect(element).not.toHaveAccessibleDescription()
  })

  expect(element).not.toHaveAttribute('aria-disabled')
}

// sometimes the we need to wait for the component to settle
export async function assertWaitForButtonToBeInLoadingState(element: HTMLElement, loadingText: string) {
  await waitFor(() => {
    expect(element).toHaveAccessibleDescription(loadingText)
  })

  expect(element).toHaveAttribute('aria-disabled', 'true')
}
