import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {http, HttpResponse} from 'msw'

import {AssessmentResultPage} from '../../components/AssessmentResultPage'
import {getAssessment, getCost, mockServer} from '../../test-utils/mock-data'

describe('AssessmentResultPage', () => {
  const setDate = '2025-05-21T23:00:00Z'
  beforeAll(() => {
    mockServer.listen({onUnhandledRequest: 'bypass'})
    jest.useFakeTimers().setSystemTime(new Date(setDate))
  })
  afterEach(() => {
    mockServer.resetHandlers()
    mockServer.events.removeAllListeners()
  })
  afterAll(() => {
    mockServer.close()
    jest.useRealTimers()
  })

  it('renders a loading state when an assessment is queued', async () => {
    const {user} = render(
      <AssessmentResultPage
        assessment={getAssessment({is_complete: false, total_scans_wanted: 2, total_scans_completed: 0})}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
      />,
    )
    expect(screen.getByText(/Queued to start/)).toBeInTheDocument()
    expect(screen.getAllByTestId('data-card-loading-skeleton')).toHaveLength(6)
    expect(screen.queryByText('Token leaks')).not.toBeInTheDocument()
    expect(screen.getByLabelText(/Token leaks scan in progress/)).toBeInTheDocument()
    const banner = screen.queryByText("Scan in progress, we'll email you when it's ready.")
    expect(banner).toBeInTheDocument()
    const dismissButton = screen.getByLabelText('Dismiss banner')
    expect(dismissButton).toBeInTheDocument()

    await user.click(dismissButton)

    expect(banner).not.toBeInTheDocument()

    await user.click(screen.getByTestId('assessment-more-options'))

    expect(screen.queryByText('Download CSV')).not.toBeInTheDocument()
  })

  it('renders a partial results state when an assessment is running', async () => {
    const {user} = render(
      <AssessmentResultPage
        assessment={getAssessment({is_complete: false, total_scans_wanted: 2, total_scans_completed: 1})}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
      />,
    )
    expect(screen.getByText(/Scan 50% complete/)).toBeInTheDocument()
    expect(screen.queryAllByTestId('data-card-loading-skeleton')).toHaveLength(0)
    expect(screen.getByText('Token leaks')).toBeInTheDocument()
    expect(screen.queryByLabelText(/Token leaks scan in progress/)).not.toBeInTheDocument()
    const banner = screen.queryByText("Scan in progress, we'll email you when it's ready.")
    expect(banner).toBeInTheDocument()
    const dismissButton = screen.getByLabelText('Dismiss banner')
    expect(dismissButton).toBeInTheDocument()

    await user.click(dismissButton)

    expect(banner).not.toBeInTheDocument()

    await user.click(screen.getByTestId('assessment-more-options'))

    expect(screen.queryByText('Download CSV')).not.toBeInTheDocument()
  })

  it('renders complete state', async () => {
    const {user} = render(
      <AssessmentResultPage assessment={getAssessment()} cost={getCost()} helpUrl="foo" org="github" />,
    )
    expect(screen.getByText(/Scan completed/)).toBeInTheDocument()
    expect(screen.queryAllByTestId('data-card-loading-skeleton')).toHaveLength(0)
    expect(screen.getByText('Token leaks')).toBeInTheDocument()
    expect(screen.queryByLabelText(/Token leaks scan in progress/)).not.toBeInTheDocument()

    await user.click(screen.getByTestId('assessment-more-options'))

    expect(screen.getByText('Download CSV')).toBeInTheDocument()
    const banner = screen.queryByText("Scan in progress, we'll email you when it's ready.")
    expect(banner).not.toBeInTheDocument()
  })

  const nextRunAvailableTests = [
    {daysDelta: 100, expectedText: 'in 3 months'},
    {daysDelta: -90, expectedText: 'now'},
  ]

  it.each(nextRunAvailableTests)(
    'displays correct next run available when it became available $daysDelta days from now',
    async ({daysDelta, expectedText}) => {
      const nextRequestAt = new Date()
      // Use UTC date so that it matches CI's timezone
      nextRequestAt.setDate(nextRequestAt.getUTCDate() + daysDelta)
      const assessment = getAssessment({
        can_request_another_assessment: true,
        next_request_available_at: nextRequestAt.toISOString(),
      })
      const {user} = render(
        <AssessmentResultPage assessment={assessment} cost={getCost()} helpUrl="foo" org="github" />,
      )

      await user.click(screen.getByTestId('assessment-more-options'))

      const relativeTimeElement = screen.getByText('Next run available')
      expect(relativeTimeElement).toBeInTheDocument()
      // eslint-disable-next-line testing-library/no-node-access
      const relativeTimeComponent = relativeTimeElement.querySelector('relative-time')
      expect(relativeTimeComponent?.shadowRoot).toHaveTextContent(expectedText)
    },
  )

  it('shows error banner if rerun scan fails', async () => {
    mockServer.use(
      http.post('/orgs/:org/security/assessments', _info => {
        return HttpResponse.json(null, {status: 500})
      }),
    )
    const {user} = render(
      <AssessmentResultPage
        assessment={getAssessment({can_request_another_assessment: true})}
        cost={getCost()}
        helpUrl="foo"
        org="github"
      />,
    )
    expect(screen.getByText(/Scan completed/)).toBeInTheDocument()

    await user.click(screen.getByLabelText('More assessment options'))
    await user.click(screen.getByRole('menuitem', {name: /Rerun scan/}))

    await waitFor(() => {
      expect(screen.getByText(/Failed to rerun scan/)).toBeInTheDocument()
    })
  })

  it('shows give feedback link by default', () => {
    render(
      <AssessmentResultPage assessment={getAssessment()} cost={getCost()} helpUrl="https://github.com" org="github" />,
    )
    expect(screen.getByText('Give feedback')).toBeInTheDocument()
  })

  it('hides give feedback link when isEnterpriseOrMT is true', () => {
    render(
      <AssessmentResultPage
        assessment={getAssessment()}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
        isEnterpriseOrMT
      />,
    )
    expect(screen.queryByText('Give feedback')).not.toBeInTheDocument()
  })

  it('shows public repo option in dropdown by default', async () => {
    const {user} = render(
      <AssessmentResultPage
        assessment={getAssessment({total_tokens_found: 1})}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
      />,
    )

    const enableButtons = screen.getAllByRole('button', {name: /Enable Secret Protection/})
    expect(enableButtons[0]).toBeInTheDocument()
    await user.click(enableButtons[0]!)

    expect(screen.getByText('For public repositories for free')).toBeInTheDocument()
  })

  it('hides public repo option in dropdown when isEnterpriseOrMT is true', async () => {
    const {user} = render(
      <AssessmentResultPage
        assessment={getAssessment({total_tokens_found: 1})}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
        isEnterpriseOrMT
      />,
    )

    const enableButtons = screen.getAllByRole('button', {name: /Enable Secret Protection/})
    expect(enableButtons[0]).toBeInTheDocument()
    await user.click(enableButtons[0]!)

    expect(screen.queryByText('For public repositories for free')).not.toBeInTheDocument()
    expect(screen.getByText('For all repositories')).toBeInTheDocument()
  })

  it('shows enable secret protection CTA when showEnableSecretProtectionButton is true', () => {
    const assessment = getAssessment({
      is_complete: true,
      total_tokens_found: 5,
    })

    render(
      <AssessmentResultPage
        assessment={assessment}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
        showEnableSecretProtectionButton
      />,
    )

    expect(screen.getAllByRole('button', {name: /Enable Secret Protection/})).toHaveLength(2)
    expect(screen.getAllByRole('link', {name: /Learn more/})).toHaveLength(2)
  })

  it('hides enable secret protection CTA and learn more link when showEnableSecretProtectionButton is false', () => {
    const assessment = getAssessment({
      is_complete: true,
      total_tokens_found: 5,
    })

    render(
      <AssessmentResultPage
        assessment={assessment}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
        showEnableSecretProtectionButton={false}
      />,
    )

    expect(screen.queryAllByRole('button', {name: /Enable Secret Protection/})).toHaveLength(0)
    expect(screen.queryByRole('link', {name: /Learn more/})).not.toBeInTheDocument()
  })

  it('shows admin contact message when showEnableSecretProtectionButton is false', () => {
    const assessment = getAssessment({
      is_complete: true,
      total_tokens_found: 5,
    })

    render(
      <AssessmentResultPage
        assessment={assessment}
        cost={getCost()}
        helpUrl="https://docs.github.com"
        org="github"
        showEnableSecretProtectionButton={false}
      />,
    )

    expect(screen.getByText('Protect your repositories from future leaks with Secret Protection')).toBeInTheDocument()
    expect(
      screen.getByText(/Contact your enterprise license administrator to enable Secret Protection/),
    ).toBeInTheDocument()
    expect(screen.getByText(/to obtain the right licenses/)).toBeInTheDocument()

    const contactLink = screen.getByRole('link', {name: 'contact GitHub'})
    expect(contactLink).toBeInTheDocument()
    expect(contactLink).toHaveAttribute('href', 'https://github.com/enterprise/contact')
  })

  it('shows admin contact banner when showEnableSecretProtectionButton is false for no leaks experience', () => {
    const assessment = getAssessment({
      is_complete: true,
      total_tokens_found: 0,
    })

    render(
      <AssessmentResultPage
        assessment={assessment}
        cost={getCost()}
        helpUrl="https://docs.github.com"
        org="github"
        showEnableSecretProtectionButton={false}
      />,
    )

    expect(screen.getByText('Protect your repositories from future leaks with Secret Protection')).toBeInTheDocument()
    expect(
      screen.getByText(/Contact your enterprise license administrator to enable Secret Protection/),
    ).toBeInTheDocument()
    expect(screen.getByText(/to obtain the right licenses/)).toBeInTheDocument()

    const contactLink = screen.getByRole('link', {name: 'contact GitHub'})
    expect(contactLink).toBeInTheDocument()
    expect(contactLink).toHaveAttribute('href', 'https://github.com/enterprise/contact')
  })

  it('does not show loading state for data cards when assessment is complete with zero scans', () => {
    // This reproduces the bug: complete assessment with zero scans (e.g., no repositories)
    // should not show loading stateAdd commentMore actions
    render(
      <AssessmentResultPage
        assessment={getAssessment({
          is_complete: true,
          total_scans_wanted: 0,
          total_scans_completed: 0,
          total_tokens_found: 0,
        })}
        cost={getCost()}
        helpUrl="https://github.com"
        org="github"
      />,
    )

    expect(screen.getByText(/Scan completed/)).toBeInTheDocument()
    // Data cards should not be in loading state when assessment is complete
    expect(screen.queryAllByTestId('data-card-loading-skeleton')).toHaveLength(0)
  })
})
