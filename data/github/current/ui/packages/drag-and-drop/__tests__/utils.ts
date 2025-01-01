import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {act, screen, within} from '@testing-library/react'

import type {DragAndDropMoveOptions} from '../utils/types'

const userEvent = setupUserEvent()

export async function selectMoveAction(action: DragAndDropMoveOptions | string) {
  await userEvent.selectOptions(screen.getByRole('combobox', {name: 'Action *'}), action)

  act(() => jest.runAllTimers())
}

export async function selectRow(rowNumber?: number | string) {
  const element = screen.getByRole('spinbutton', {name: 'Move to position *'})
  await userEvent.clear(element)
  if (rowNumber !== undefined) {
    await userEvent.type(element, `${rowNumber}`)
  }

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

// TODO: replace with `selectBefore` now that we are using a select instead of autocomplete
export async function selectBeforeExperimental(title?: string) {
  const element = screen.getByRole('combobox', {name: 'Move item before *'})
  if (title) {
    await userEvent.selectOptions(element, title)
  }
  await userEvent.keyboard('{Enter}')

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

export async function selectBefore(title?: string) {
  const element = screen.getByRole('combobox', {name: 'Move item before *'})
  await userEvent.clear(element)
  if (title) {
    await userEvent.type(element, title)
  }
  await userEvent.keyboard('{Enter}')

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

// TODO: replace with `selectAfter` now that we are using a select instead of autocomplete
export async function selectAfterExperimental(title?: string) {
  const element = screen.getByRole('combobox', {name: 'Move item after *'})
  if (title) {
    await userEvent.selectOptions(element, title)
  }
  await userEvent.keyboard('{Enter}')

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

export async function selectAfter(title?: string) {
  const element = screen.getByRole('combobox', {name: 'Move item after *'})
  await userEvent.clear(element)
  if (title) {
    await userEvent.type(element, title)
  }
  await userEvent.keyboard('{Enter}')

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

export async function submitDialog() {
  await userEvent.click(screen.getByRole('button', {name: 'Move'}))

  act(() => jest.runAllTimers())
}

export function expectAnnouncement(announcement: string) {
  expect(screen.getByTestId('js-global-screen-reader-notice-assertive')).toHaveTextContent(announcement)
}

export function expectErrorMessage(message: string) {
  expect(within(screen.getByRole('dialog')).getByText(message)).toBeInTheDocument()
}

export function expectFlashMessage(message: string) {
  expect(screen.getByTestId('drag-and-drop-move-dialog-flash')).toHaveTextContent(message)
}
