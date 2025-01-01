import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {mockRelease} from '../../../test-utils/mock-data'
import {ReleaseBanner} from '../../actions/ReleaseBanner'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {marketplaceActionPath} from '@github-ui/paths'

describe('ReleaseBanner', () => {
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

  const props = {
    action: mockActionListing({slug: 'test-action'}),
    selectedRelease: mockRelease({tagName: 'v1.0.0'}),
    latestRelease: mockRelease({tagName: 'v2.0.0'}),
  }

  describe('When there is a selected release', () => {
    describe('When the selected release is not the latest release', () => {
      describe('When the action has a slug', () => {
        it('Renders warning with a link to latest version', () => {
          render(<ReleaseBanner {...props} />)

          expect(
            screen.getByText(/You're viewing an older version of this GitHub Action. Do you want to see the/i),
          ).toBeInTheDocument()
          expect(screen.getByRole('link', {name: /latest version/i})).toHaveAttribute(
            'href',
            marketplaceActionPath({slug: 'test-action'}),
          )
          expect(screen.getByText(/instead/i)).toBeInTheDocument()
        })
      })

      describe('When the action does not have a slug', () => {
        it('Does not render warning', () => {
          render(<ReleaseBanner {...props} action={{...props.action, slug: undefined}} />)

          expect(
            screen.queryByText(/You're viewing an older version of this GitHub Action. Do you want to see the/i),
          ).not.toBeInTheDocument()
          expect(screen.queryByRole('link', {name: /latest version/i})).not.toBeInTheDocument()
          expect(screen.queryByText(/instead/i)).not.toBeInTheDocument()
        })
      })
    })

    describe('When the selected release is the latest release', () => {
      it('Does not render warning', () => {
        render(<ReleaseBanner {...props} selectedRelease={props.latestRelease} />)

        expect(
          screen.queryByText(/You're viewing an older version of this GitHub Action. Do you want to see the/i),
        ).not.toBeInTheDocument()
        expect(screen.queryByRole('link', {name: /latest version/i})).not.toBeInTheDocument()
        expect(screen.queryByText(/instead/i)).not.toBeInTheDocument()
      })
    })
  })

  describe('When there is no selected release', () => {
    it('Does not render warning', () => {
      render(<ReleaseBanner {...props} selectedRelease={undefined} />)

      expect(
        screen.queryByText(/You're viewing an older version of this GitHub Action. Do you want to see the/i),
      ).not.toBeInTheDocument()
      expect(screen.queryByRole('link', {name: /latest version/i})).not.toBeInTheDocument()
      expect(screen.queryByText(/instead/i)).not.toBeInTheDocument()
    })
  })
})
