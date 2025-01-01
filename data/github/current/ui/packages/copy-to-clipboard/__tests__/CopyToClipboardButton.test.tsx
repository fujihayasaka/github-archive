import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {announce} from '@github-ui/aria-live'

import {CopyToClipboardButton} from '../CopyToClipboardButton'

const copyFn = jest.fn()
jest.mock('../copy', () => {
  return {
    copyText: () => copyFn,
  }
})

jest.mock('@github-ui/aria-live', () => ({
  announce: jest.fn(),
}))

describe('CopyToClipboard Button', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('Renders the button', () => {
    render(<CopyToClipboardButton ariaLabel="demo copy" textToCopy="hello" />)
    const button = screen.getByRole('button', {name: 'demo copy'})
    expect(button).toBeDefined()
  })

  test('hides tooltip from assistive tech', () => {
    render(<CopyToClipboardButton ariaLabel="demo copy" textToCopy="hello" />)
    const tooltip = screen.queryByRole('tooltip')
    expect(tooltip).toBeNull()
  })

  test('Renders disabled button', () => {
    render(<CopyToClipboardButton ariaLabel="demo copy" textToCopy="hello" disabled />)
    const button = screen.getByRole('button', {name: 'demo copy'})
    expect(button).toBeDisabled()
  })

  test('when pressed, the accessible name does not change but visible tooltip text changes', () => {
    render(<CopyToClipboardButton ariaLabel="copy to clipboard" textToCopy="hello" />)
    const button = screen.getByRole('button', {name: 'copy to clipboard'})
    act(() => {
      button.click()
    })
    expect(screen.getByText('Copied!')).toBeDefined()
    expect(button).toHaveAccessibleName('copy to clipboard')
  })

  test('when pressed, announce function should be called', () => {
    render(<CopyToClipboardButton ariaLabel="copy to clipboard" textToCopy="hello" />)
    const button = screen.getByRole('button', {name: 'copy to clipboard'})
    act(() => {
      button.click()
    })
    expect(announce).toHaveBeenCalledWith('Copied!')
    expect(announce).toHaveBeenCalledTimes(1)
  })
})
