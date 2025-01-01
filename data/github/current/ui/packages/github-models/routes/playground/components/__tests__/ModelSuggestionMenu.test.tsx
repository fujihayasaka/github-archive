import {ModelSuggestionMenu} from '../ModelSuggestionMenu'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../__tests__/mocks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {PlaygroundChatSuggestion} from '../../../../utils/playground-types'

const mockSetSearchParams = jest.fn()
const mockSearchParamsFn = [new URLSearchParams(''), mockSetSearchParams]
jest.mock('@github-ui/use-navigate', () => {
  return {
    useSearchParams: () => mockSearchParamsFn,
  }
})
afterEach(() => {
  jest.clearAllMocks()
})

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

describe('ModelSuggestionMenu', () => {
  it('renders the list of suggested models', async () => {
    const task = 'Make response faster'
    const action = 'make_response_faster'
    const spy = jest.spyOn(URLSearchParams.prototype, 'set')
    const {user} = render(<ModelSuggestionMenu task={task} suggestedModels={[mockModel]} action={action} />)

    await user.click(screen.getByText(task))

    const model = screen.getByText(mockModel.friendly_name)
    expect(model).toBeInTheDocument()

    await user.click(model)

    expect(spy).toHaveBeenCalledWith('compare_to', mockModel.name)
    expect(spy).toHaveBeenCalledWith('resend-user-prompt', 'true')
    expect(mockSetSearchParams).toHaveBeenCalledTimes(1)

    expect(sendEvent).toHaveBeenCalledWith(`${PlaygroundChatSuggestion}.${action}.clicked`)
  })
})
