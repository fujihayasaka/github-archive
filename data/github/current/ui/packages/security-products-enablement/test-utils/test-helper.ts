// Adapted from https://github.com/primer/react/blob/main/packages/react/src/Banner/Banner.test.tsx:
// Remove when https://github.com/github/primer/issues/3882 is resolved
export function swallowCSSParsingError() {
  // Note: this error occurs due to our usage of `@container` within a
  // `<style>` tag in Banner. The CSS parser for jsdom does not support this
  // syntax and will fail with an error containing the message below.
  // eslint-disable-next-line no-console
  const originalConsoleError = console.error
  jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
    if (!value?.message?.includes('Could not parse CSS stylesheet')) {
      originalConsoleError(value, ...args)
    }
  })
}
