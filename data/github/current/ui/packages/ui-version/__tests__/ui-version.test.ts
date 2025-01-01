import '../ui-version'

test('ui-version', () => {
  expect((globalThis as {UI_VERSION?: string}).UI_VERSION).toBe('dotcom')
})
