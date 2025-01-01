import {render, within} from '@testing-library/react'
import {PlaygroundTokenUsageWidget} from '../PlaygroundTokenUsageWidget'
import {mockModelState} from './mocks'
import {mockModel} from '../../__tests__/mocks'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {Panel} from '../../../../utils/playground-manager'

describe('PlaygroundTokenUsageWidget', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders', () => {
    const model = Object.assign({}, mockModel, {capabilities: {tokenCounting: true}})
    const modelState = mockModelState({isLoading: false, catalogData: model})

    const {container} = render(
      <Wrapper>
        <PlaygroundTokenUsageWidget modelState={modelState} position={Panel.Main} />
      </Wrapper>,
    )

    expect(within(container).getByTestId('playground-token-usage')).toBeInTheDocument()
  })
})
