import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {AppearanceSettingsDialog} from '../AppearanceSettingsDialog.stories'

// '@github-ui/cookies' throws an error if `document.domain` is not defined, and it isn’t defined in JSDOM
jest.mock('@github-ui/cookies')

async function setup(): Promise<{
  dialog: HTMLElement
  increaseContrastSwitch: HTMLElement
  lightModeSwitch: HTMLElement
  darkModeSwitch: HTMLElement
}> {
  // Render the AppearanceSettingsDialog component
  render(<AppearanceSettingsDialog />)

  // Open the dialog
  const button = screen.getByRole('button', {name: 'Appearance settings'})
  act(() => button.click())

  // Assert the dialog contains expected controls
  const dialog = screen.getByRole('dialog', {name: 'Appearance settings'})
  const increaseContrastSwitch = screen.getByRole('button', {name: 'Increase contrast'})
  const lightModeSwitch = screen.getByRole('button', {name: 'Light mode'})
  const darkModeSwitch = screen.getByRole('button', {name: 'Dark mode'})
  expect(dialog).toBeInTheDocument()
  expect(increaseContrastSwitch).toBeInTheDocument()
  expect(lightModeSwitch).toBeInTheDocument()
  expect(darkModeSwitch).toBeInTheDocument()

  // Return elements to support making assertions
  return {
    dialog,
    increaseContrastSwitch,
    lightModeSwitch,
    darkModeSwitch,
  }
}

test('When the main toggle is "Off", activating it changes both mode toggles to "On"', async () => {
  // Render the AppearanceSettingsDialog component
  const {increaseContrastSwitch, lightModeSwitch, darkModeSwitch} = await setup()

  // Assert the dialog’s initial state (all "Off")
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('false')

  // Change the main toggle to "On"
  act(() => increaseContrastSwitch.click())

  // Assert all toggles are "On"
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('true')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('true')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('true')
})

test('When the main toggle is "Off", activating either mode toggle changes the main toggle to "On", and the activated mode toggle will be "On" (the other will remain "Off")', async () => {
  // Render the AppearanceSettingsDialog component
  const {increaseContrastSwitch, lightModeSwitch, darkModeSwitch} = await setup()

  // Assert the dialog’s initial state (all "Off")
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('false')

  // Toggle one mode toggle to "On"
  act(() => lightModeSwitch.click())

  // Assert that the main toggle is "On" and only one mode toggle is "On"
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('true')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('true')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('false')
})

test('When the main toggle is "On", toggling both mode toggles to "Off" changes the main toggle to "Off"', async () => {
  // Render the AppearanceSettingsDialog component
  const {increaseContrastSwitch, lightModeSwitch, darkModeSwitch} = await setup()

  // Assert the dialog’s initial state (all "Off")
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('false')

  // Toggle the main toggle to "On"
  act(() => increaseContrastSwitch.click())

  // Assert all toggles are "On"
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('true')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('true')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('true')

  // Toggle both mode toggles to "Off"
  act(() => {
    lightModeSwitch.click()
    darkModeSwitch.click()
  })

  // Assert all toggles are "Off"
  expect(increaseContrastSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(lightModeSwitch.getAttribute('aria-pressed')).toBe('false')
  expect(darkModeSwitch.getAttribute('aria-pressed')).toBe('false')
})
