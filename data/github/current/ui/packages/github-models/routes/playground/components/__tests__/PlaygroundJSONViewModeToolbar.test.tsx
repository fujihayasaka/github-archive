import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundJSONViewModeToolbar} from '../PlaygroundJSONViewModeToolbar'

describe('PlaygroundJSONViewModeToolbar', () => {
  const doEdit = jest.fn().mockName('doEdit')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders', async () => {
    const {container, user} = render(<PlaygroundJSONViewModeToolbar doEdit={doEdit} />)

    expect(doEdit).not.toHaveBeenCalled()
    const editButton = within(container).getByRole('button', {name: 'Edit JSON'})
    expect(editButton).toBeInTheDocument()

    await user.click(editButton)

    expect(doEdit).toHaveBeenCalledTimes(1)
  })
})
