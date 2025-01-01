import {screen, waitFor} from '@testing-library/react'
import type {User} from '@github-ui/react-core/test-utils'

class IntersectionObserver {
  root = null
  rootMargin = ''
  thresholds = []

  disconnect() {
    return null
  }

  observe() {
    return null
  }

  takeRecords() {
    return []
  }

  unobserve() {
    return null
  }
}

export function setupIntersectionObserverMock(): void {
  class MockIntersectionObserver implements IntersectionObserver {
    root = null
    rootMargin = ''
    thresholds = []
    disconnect: () => null = () => null
    observe: () => null = () => null
    takeRecords: () => never[] = () => []
    unobserve: () => null = () => null
  }

  Object.defineProperty(window, 'IntersectionObserver', {
    writable: true,
    configurable: true,
    value: MockIntersectionObserver,
  })

  Object.defineProperty(global, 'IntersectionObserver', {
    writable: true,
    configurable: true,
    value: MockIntersectionObserver,
  })
}

export function setupResizeObserverMock() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }

  Object.defineProperty(window, 'ResizeObserver', {
    writable: true,
    configurable: true,
    value: MockResizeObserver,
  })
}

export async function clickPickerButton(user: User) {
  const button = await screen.findByRole('button', {name: /[All|Select] repositories/})
  await user.click(button)

  await screen.findByRole('menu')
}

export async function clickMenuItem(user: User, which: 'selected' | 'all') {
  const pattern = which === 'selected' ? 'Selected repositories' : 'All repositories'
  const name = new RegExp(pattern)

  const menuItem = await screen.findByRole('menuitemradio', {name})
  await user.click(menuItem)
}

export async function openPicker(user: User) {
  await clickPickerButton(user)

  await clickMenuItem(user, 'selected')

  await waitFor(async () => expect(await screen.findByRole('dialog')).toBeInTheDocument())
}

export async function openList(user: User, {count = 1}: {count: number}) {
  const button = await screen.findByText(`Repositories: ${count} selected`)
  await user.click(button)

  await waitFor(async () => expect(await screen.findByRole('dialog')).toBeInTheDocument())
}
