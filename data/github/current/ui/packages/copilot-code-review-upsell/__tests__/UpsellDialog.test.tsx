import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {UpsellDialog} from '../UpsellDialog'
import {MockUpsellData} from './mock-data'

jest.mock('@github-ui/copilot-code-review-upsell/hooks', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/utils/copilot-chat-events'),
    useShowUpsellDialog: () => [true, () => {}],
  }
})

describe('UpsellDialog', () => {
  test('individual pro', async () => {
    render(<UpsellDialog {...MockUpsellData} />)
    const limitText = screen.queryByText(
      'You have reached your monthly limit for premium requests for Copilot code review.',
      {exact: false},
    )
    expect(limitText).toBeInTheDocument()
  })
})
