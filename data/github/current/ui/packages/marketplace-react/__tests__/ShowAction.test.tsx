import {ShowAction} from '../routes/ShowAction'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getShowActionRoutePayload} from '../test-utils/mock-data'

describe('ShowAction', () => {
  // Needed because this component renders ui/packages/marketplace-react/components/actions/ReleaseBanner.tsx
  // Copied from https://github.com/primer/react/blob/main/packages/react/src/Banner/Banner.test.tsx:
  beforeEach(() => {
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
  })

  test('Renders the ListingLayout component', () => {
    const routePayload = getShowActionRoutePayload()
    render(<ShowAction />, {
      routePayload,
    })

    expect(screen.getByTestId('marketplace-listing')).toBeInTheDocument()
  })
})
