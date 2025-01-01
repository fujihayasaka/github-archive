import {render, within} from '@testing-library/react'
import {PlaygroundTokenUsageWidget} from '../PlaygroundTokenUsageWidget'
import {mockModelState} from './mocks'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {Panel} from '../../../../utils/playground-manager'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

describe('PlaygroundTokenUsageWidget', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders when feature is enabled', () => {
    mockUseFeatureFlag.mockReturnValue(true)

    const modelState = mockModelState({isLoading: false})
    const {container} = render(
      <Wrapper>
        <PlaygroundTokenUsageWidget modelState={modelState} position={Panel.Main} />
      </Wrapper>,
    )

    expect(within(container).getByTestId('playground-token-usage')).toBeInTheDocument()
  })

  test('does not render when feature is disabled', () => {
    mockUseFeatureFlag.mockReturnValue(false)

    const modelState = mockModelState({isLoading: false})
    const {container} = render(
      <Wrapper>
        <PlaygroundTokenUsageWidget modelState={modelState} position={Panel.Main} />
      </Wrapper>,
    )

    expect(within(container).queryByTestId('playground-token-usage')).not.toBeInTheDocument()
  })
})
