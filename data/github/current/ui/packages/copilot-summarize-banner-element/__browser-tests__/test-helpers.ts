import {assert} from '@github-ui/browser-tests'

export function assertShown(element: HTMLElement | undefined, message?: string) {
  assert.instanceOf(element, HTMLElement)
  assert.isFalse(element?.hidden, message ?? 'should have shown element')
}

export function assertHidden(element: HTMLElement | undefined, message?: string) {
  assert.instanceOf(element, HTMLElement)
  assert.isTrue(element?.hidden, message ?? 'should have hidden element')
}

export function assertShownButton(button: HTMLElement | undefined, message?: string) {
  assert.instanceOf(button, HTMLButtonElement)
  assert.isFalse(button?.hidden, message ?? 'should have shown button')
}

export function assertHiddenButton(button: HTMLElement | undefined, message?: string) {
  assert.instanceOf(button, HTMLButtonElement)
  assert.isTrue(button?.hidden, message ?? 'should have hidden button')
}

export function assertEnabled(button: HTMLButtonElement | undefined, message?: string) {
  assert.instanceOf(button, HTMLButtonElement)
  assert.isFalse(button?.disabled, message ?? 'should have enabled button')
}

export function assertDisabled(button: HTMLButtonElement | undefined, message?: string) {
  assert.instanceOf(button, HTMLButtonElement)
  assert.isTrue(button?.disabled, message ?? 'should have disabled button')
}
