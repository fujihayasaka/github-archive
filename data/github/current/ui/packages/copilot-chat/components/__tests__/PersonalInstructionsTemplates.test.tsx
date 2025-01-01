import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {suggestedPersonalInstructions} from '../../utils/custom-instructions'
import {PersonalInstructionsTemplates} from '../PersonalInstructionsTemplates'

const userEvent = setupUserEvent()

describe('PersonalInstructionsTemplates', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders a personal instruction templates based on the data', async () => {
    const onSelectMock = jest.fn()

    renderPersonalInstructionsTemplates({onSelect: onSelectMock})

    await userEvent.click(screen.getByTestId('toggle-templates'))

    for (const key of Object.keys(suggestedPersonalInstructions)) {
      expect(screen.getByText(key)).toBeInTheDocument()
    }
  })

  test('selects a template', async () => {
    const onSelectMock = jest.fn()

    renderPersonalInstructionsTemplates({onSelect: onSelectMock})

    await userEvent.click(screen.getByTestId('toggle-templates'))

    for (const key of Object.keys(suggestedPersonalInstructions)) {
      await userEvent.click(screen.getByText(key))

      expect(onSelectMock).toHaveBeenCalledWith(key, suggestedPersonalInstructions[key]?.body)
    }
  })

  function renderPersonalInstructionsTemplates(props = {}) {
    render(<PersonalInstructionsTemplates onSelect={() => {}} {...props} />)
  }
})
