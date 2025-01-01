import {render} from '@github-ui/react-core/test-utils'
import FeaturesCopilotIndex from '../../routes/features/copilot/Index'
import {act, screen} from '@testing-library/react'
import featuresCopilotPagePayload from '../fixtures/routes/FeaturesCopilotPage/indexPagePayload'
import {fetchVariant} from '../../utils'

// Mock the fetchVariant function
jest.mock('../../utils', () => ({
  fetchVariant: jest.fn(),
}))

// Mock the THREE.WebGLRenderer class
jest.mock('three', () => {
  const originalThree = jest.requireActual('three')
  return {
    ...originalThree,
    WebGLRenderer: jest.fn().mockImplementation(() => ({
      setSize: jest.fn(),
      render: jest.fn(),
      dispose: jest.fn(),
      setPixelRatio: jest.fn(),
      setClearColor: jest.fn(),
      domElement: document.createElement('canvas'),
    })),
  }
})

describe('FeaturesCopilotIndex', () => {
  beforeEach(() => {
    // Mock the play method for HTMLMediaElement
    Object.defineProperty(HTMLMediaElement.prototype, 'play', {
      configurable: true,
      value: jest.fn().mockImplementation(() => Promise.resolve()),
    })

    // Mock the pause method for HTMLMediaElement
    Object.defineProperty(HTMLMediaElement.prototype, 'pause', {
      configurable: true,
      value: jest.fn().mockImplementation(() => Promise.resolve()),
    })
  })

  it('renders CTAs when logged out', async () => {
    ;(fetchVariant as jest.Mock).mockResolvedValue('single_btn_copilot_plans')

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<FeaturesCopilotIndex />, {
        routePayload: {
          logged_in: false,
          contentfulRawJsonResponse: featuresCopilotPagePayload.contentfulRawJsonResponse,
        },
      })
    })

    expect(screen.getByTestId('primary-btn-copilot-start-free')).toBeInTheDocument()
    expect(screen.getByTestId('secondary-btn-copilot-plans')).toBeInTheDocument()
  })
})
