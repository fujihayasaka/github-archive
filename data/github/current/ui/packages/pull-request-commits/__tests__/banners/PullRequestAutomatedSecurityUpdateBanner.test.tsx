import {screen} from '@testing-library/react'
import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'

import {PullRequestAutomatedSecurityUpdateBanner} from '../../components/banners/PullRequestAutomatedSecurityUpdateBanner'
import {getCommitsRoutePayload} from '../../test-utils/mock-data'

describe('PullRequestBanners', () => {
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

  const {bannersData} = getCommitsRoutePayload()
  bannersData.banners.dependabotAutomatedSecurityUpdates.render = true

  const defaultDependabotUpdates = bannersData.banners.dependabotAutomatedSecurityUpdates

  test('renders without errors', () => {
    const {pullRequest} = getCommitsRoutePayload()
    renderWithClient(
      <PullRequestAutomatedSecurityUpdateBanner
        dependabotUpdates={defaultDependabotUpdates}
        pullRequest={pullRequest}
      />,
    )

    expect(screen.getByText(/this pull request will resolve/)).toBeInTheDocument()
    expect(screen.getByText(/a Dependabot alert/)).toBeInTheDocument()
  })

  test('leading text changes tense on pull request state', () => {
    const {pullRequest} = getCommitsRoutePayload()
    pullRequest.state = 'merged'

    renderWithClient(
      <PullRequestAutomatedSecurityUpdateBanner
        dependabotUpdates={defaultDependabotUpdates}
        pullRequest={pullRequest}
      />,
    )

    expect(screen.getByText(/This pull request resolved/)).toBeInTheDocument()
    expect(screen.getByText(/a Dependabot alert/)).toBeInTheDocument()
  })

  test('leading text changes implies a resolution if pull request is closed', () => {
    const {pullRequest} = getCommitsRoutePayload()
    pullRequest.state = 'closed'

    renderWithClient(
      <PullRequestAutomatedSecurityUpdateBanner
        dependabotUpdates={defaultDependabotUpdates}
        pullRequest={pullRequest}
      />,
    )

    expect(screen.getByText(/This pull request would resolve/)).toBeInTheDocument()
    expect(screen.getByText(/a Dependabot alert/)).toBeInTheDocument()
  })

  test('a present alert changes the render', () => {
    const {pullRequest} = getCommitsRoutePayload()
    defaultDependabotUpdates.alertPresent = true

    renderWithClient(
      <PullRequestAutomatedSecurityUpdateBanner
        dependabotUpdates={defaultDependabotUpdates}
        pullRequest={pullRequest}
      />,
    )

    expect(screen.queryByText(/a Dependabot alert/)).not.toBeInTheDocument()
  })

  test('a single alert renders as expected', () => {
    const {pullRequest} = getCommitsRoutePayload()

    const singleAlert = {
      ...defaultDependabotUpdates,
      alertPresent: true,
      singleAlert: true,
      severity: 'very severe',
      packageName: 'react-pkg',
      securityAlertPath: '/monalisa/smile/security/dependabot/12345',
    }

    renderWithClient(
      <PullRequestAutomatedSecurityUpdateBanner dependabotUpdates={singleAlert} pullRequest={pullRequest} />,
    )

    expect(screen.getByText(/very severe/)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Dependabot Alert'})).toBeInTheDocument()
    expect(screen.getByText(/on react-pkg/)).toBeInTheDocument()
  })

  test('multiple alerts render as expected', () => {
    const {pullRequest} = getCommitsRoutePayload()

    const multiAlert = {
      ...defaultDependabotUpdates,
      alertPresent: true,
      singleAlert: false,
      severity: 'very severe',
      packageName: 'react-pkg',
      securityAlertPath: '/monalisa/smile/security/dependabot/12345',
    }

    renderWithClient(
      <PullRequestAutomatedSecurityUpdateBanner dependabotUpdates={multiAlert} pullRequest={pullRequest} />,
    )

    expect(screen.getByText(/very severe/)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Dependabot Alerts'})).toBeInTheDocument()
    expect(screen.getByText(/on react-pkg/)).toBeInTheDocument()
  })
})
