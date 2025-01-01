import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

const userEvent = setupUserEvent()

export async function selectMoveAction(action: string) {
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
export async function selectBefore(title?: string) {
  const element = screen.getByRole('combobox', {name: 'Move item before *'})
  if (title) {
    await userEvent.selectOptions(element, title)
  }
  await userEvent.keyboard('{Enter}')

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

export async function selectAfter(title?: string) {
  const element = screen.getByRole('combobox', {name: 'Move item after *'})
  if (title) {
    await userEvent.selectOptions(element, title)
  }
  await userEvent.keyboard('{Enter}')

  screen.getByRole('button', {name: 'Move'}).focus()

  act(() => jest.runAllTimers())
}

export async function submitDialog() {
  await userEvent.click(screen.getByRole('button', {name: 'Move'}))

  act(() => jest.runAllTimers())
}
