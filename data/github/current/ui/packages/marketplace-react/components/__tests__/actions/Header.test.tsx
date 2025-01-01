import {Header} from '../../actions/Header'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {mockRepository, mockReleaseData, mockStarData} from '../../../test-utils/mock-data'

describe('Header', () => {
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

  const actionListing = mockActionListing()
  const repository = mockRepository()
  const releaseData = mockReleaseData()
  const starData = mockStarData()

  test('Renders the overview header', () => {
    render(
      <Header action={actionListing} repository={repository} releaseData={releaseData} loggedIn starData={starData} />,
    )

    expect(screen.getByTestId('overview-header')).toBeInTheDocument()
  })

  test('Renders the release banner', () => {
    render(
      <Header action={actionListing} repository={repository} releaseData={releaseData} loggedIn starData={starData} />,
    )

    expect(
      screen.getByText(/You're viewing an older version of this GitHub Action. Do you want to see the/i),
    ).toBeInTheDocument()
  })

  test('Renders the about section', () => {
    render(
      <Header action={actionListing} repository={repository} releaseData={releaseData} loggedIn starData={starData} />,
    )

    expect(screen.getByTestId('about')).toBeInTheDocument()
  })

  test('Renders the tags section', () => {
    render(
      <Header action={actionListing} repository={repository} releaseData={releaseData} loggedIn starData={starData} />,
    )

    expect(screen.getByTestId('tags')).toBeInTheDocument()
  })

  test('Renders the star button', () => {
    render(
      <Header action={actionListing} repository={repository} releaseData={releaseData} loggedIn starData={starData} />,
    )

    expect(screen.getByTestId('star-button')).toBeInTheDocument()
  })

  test('Renders the verified owners section', () => {
    render(
      <Header action={actionListing} repository={repository} releaseData={releaseData} loggedIn starData={starData} />,
    )

    expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
  })
})
