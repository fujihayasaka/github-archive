import {render} from '@github-ui/react-core/test-utils'
import {CopilotIndex} from '../../routes/CopilotIndex'
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

describe('CopilotIndex', () => {
  it('renders single CTA to /features/copilot/plans when logged out', async () => {
    ;(fetchVariant as jest.Mock).mockResolvedValue('single_btn_copilot_plans')

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<CopilotIndex />, {
        routePayload: {
          experimentation_copilot_alt_ctas_enabled: false,
          logged_in: false,
          contentfulRawJsonResponse: featuresCopilotPagePayload.contentfulRawJsonResponse,
        },
      })
    })

    expect(screen.getByTestId('single-btn-copilot-plans')).toBeInTheDocument()
    expect(screen.queryByTestId('dual-btn-copilot-signup')).not.toBeInTheDocument()
    expect(screen.queryByTestId('dual-btn-copilot-plans')).not.toBeInTheDocument()
  })
})
