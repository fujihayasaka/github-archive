import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import {CopilotSurvey} from '../CopilotSurvey'

// Mock the window.location.href assignment
Object.defineProperty(window, 'location', {
  writable: true,
  value: {href: ''},
})

const mockProps = {
  bannerTitle: 'Test Banner Title',
  bannerText: 'Test Banner Text',
  ctaText: 'Take Survey',
  ctaUrl: 'https://example.com/survey',
  bannerSlug: 'test-survey-slug',
  surveyOpenCallbackPath: '/copilot/feedback-survey/open',
  surveyDismissCallbackPath: '/copilot/feedback-survey/dismiss',
  icon: 'copilot',
}

// Set up MSW handlers
const handlers = [
  // Handler for the dismiss survey API call
  http.post('/copilot/feedback-survey/dismiss', async ({request}) => {
    const requestBody = (await request.json()) as {slug: string}

    // Verify the correct slug is sent in the request
    if (requestBody.slug === mockProps.bannerSlug) {
      return HttpResponse.json({success: true})
    }

    return HttpResponse.json({success: false}, {status: 400})
  }),

  // Handler for the open survey API call
  http.post('/copilot/feedback-survey/open', async ({request}) => {
    const requestBody = (await request.json()) as {slug: string}

    // Verify the correct slug is sent in the request
    if (requestBody.slug === mockProps.bannerSlug) {
      return HttpResponse.json({success: true})
    }

    return HttpResponse.json({success: false}, {status: 400})
  }),
]

const server = setupServer(...handlers)

describe('CopilotSurvey', () => {
  beforeAll(() => {
    server.listen()
  })

  beforeEach(() => {
    // Reset the href before each test
    window.location.href = ''

    // Suppress console warnings for MSW
    jest.spyOn(console, 'warn').mockImplementation(() => {})
  })

  afterEach(() => {
    server.resetHandlers()
    jest.restoreAllMocks()
  })

  afterAll(() => {
    server.close()
  })

  it('renders the banner with correct content', () => {
    render(<CopilotSurvey {...mockProps} />)

    expect(screen.getByText(mockProps.bannerTitle)).toBeInTheDocument()
    expect(screen.getByText(mockProps.bannerText)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: mockProps.ctaText})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close GrowthBanner'})).toBeInTheDocument()
  })

  it('calls the dismiss API and hides the banner when close button is clicked', async () => {
    const {user} = render(<CopilotSurvey {...mockProps} />)

    // Find and click the close button
    const closeButton = screen.getByRole('button', {name: 'Close GrowthBanner'})
    await user.click(closeButton)

    // The banner should be hidden after clicking close
    await waitFor(() => {
      expect(screen.queryByText(mockProps.bannerTitle)).not.toBeInTheDocument()
    })
  })

  it('calls the open API and redirects when CTA button is clicked', async () => {
    const {user} = render(<CopilotSurvey {...mockProps} />)

    // Find and click the CTA button
    const ctaButton = screen.getByRole('button', {name: mockProps.ctaText})
    await user.click(ctaButton)

    // Check that it navigates to the CTA URL
    expect(window.location.href).toBe(mockProps.ctaUrl)
  })

  it('still hides the banner even if dismiss API call fails', async () => {
    // Override the handler to return an error
    server.use(
      http.post(mockProps.surveyDismissCallbackPath, () => {
        return HttpResponse.error()
      }),
    )

    const {user} = render(<CopilotSurvey {...mockProps} />)

    // Find and click the close button
    const closeButton = screen.getByRole('button', {name: 'Close GrowthBanner'})
    await user.click(closeButton)

    // The banner should still be hidden even after API failure
    await waitFor(() => {
      expect(screen.queryByText(mockProps.bannerTitle)).not.toBeInTheDocument()
    })
  })

  it('still redirects even if open API call fails', async () => {
    // Override the handler to return an error
    server.use(
      http.post(mockProps.surveyOpenCallbackPath, () => {
        return HttpResponse.error()
      }),
    )

    const {user} = render(<CopilotSurvey {...mockProps} />)

    // Find and click the CTA button
    const ctaButton = screen.getByRole('button', {name: mockProps.ctaText})
    await user.click(ctaButton)

    // Check that it still navigates to the CTA URL even with API failure
    expect(window.location.href).toBe(mockProps.ctaUrl)
  })
})
