import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'
import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import {copilotWrapper as wrapper} from '../../test-utils/helpers'
import {mockCopilotImmersiveLoggedOutPayload} from '../../test-utils/mock-data'
import {ModelPicker} from '../ModelPicker'

jest.mock('@github-ui/react-core/use-app-payload')

const geminiModel = {
  capabilities: {
    family: 'gemini-2.0-flash',
    limits: {
      // eslint-disable-next-line camelcase
      max_context_window_tokens: 1000000,
      // eslint-disable-next-line camelcase
      max_output_tokens: 8192,
      // eslint-disable-next-line camelcase
      max_prompt_tokens: 128000,
      vision: {
        // eslint-disable-next-line camelcase
        max_prompt_image_size: 3145728,
        // eslint-disable-next-line camelcase
        max_prompt_images: 1,
        // eslint-disable-next-line camelcase
        supported_media_types: ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'],
      },
    },
    object: 'model_capabilities',
    // eslint-disable-next-line camelcase
    supports: {parallel_tool_calls: true, streaming: true, tool_calls: true, vision: true},
    tokenizer: 'o200k_base',
    type: 'chat',
  },
  id: 'gemini-2.0-flash-001',
  // eslint-disable-next-line camelcase
  model_picker_enabled: true,
  name: 'Gemini 2.0 Flash',
  object: 'model',
  preview: false,
  vendor: 'Google',
  version: 'gemini-2.0-flash-001',
  // eslint-disable-next-line camelcase
  is_chat_default: true,
}

mockCopilotImmersiveLoggedOutPayload.models.push(geminiModel)

describe('ModelPicker', () => {
  it('renders the ModelPicker with default value', () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<ModelPicker />, {wrapper})

    const modelPicker = screen.getByTestId('model-picker')
    expect(modelPicker).toBeVisible()

    const buttonText = generateDefaultModel().displayName
    expect(modelPicker).toHaveTextContent(buttonText)
  })

  it('renders the correct number of models and updates the correct model in ModelPicker', async () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    const {user} = render(<ModelPicker />, {wrapper})

    const modelPicker = screen.getByTestId('model-picker')
    expect(modelPicker).toBeVisible()
    expect(modelPicker).toHaveTextContent('GPT-4.1')

    const gptButton = screen.getByRole('button', {name: 'GPT-4.1'})
    await user.click(gptButton) // Opens picker

    let menuItems = screen.getAllByRole('menuitemradio')
    expect(menuItems.length).toEqual(2)

    let gptRadio = screen.getByRole('menuitemradio', {name: 'GPT-4.1'})
    expect(gptRadio).toBeInTheDocument()
    expect(gptRadio).toBeChecked()
    let geminiRadio = screen.getByRole('menuitemradio', {name: 'Gemini 2.0 Flash'})
    expect(geminiRadio).toBeInTheDocument()
    expect(geminiRadio).not.toBeChecked()

    await user.click(geminiRadio) // Picks Gemini, closes picker

    expect(modelPicker).toHaveTextContent('Gemini 2.0 Flash')

    const geminiButton = screen.getByRole('button', {name: 'Gemini 2.0 Flash'})
    await user.click(geminiButton) // Opens picker

    menuItems = screen.getAllByRole('menuitemradio')
    expect(menuItems.length).toEqual(2)

    gptRadio = screen.getByRole('menuitemradio', {name: 'GPT-4.1'})
    expect(gptRadio).toBeInTheDocument()
    expect(gptRadio).not.toBeChecked()
    geminiRadio = screen.getByRole('menuitemradio', {name: 'Gemini 2.0 Flash'})
    expect(geminiRadio).toBeInTheDocument()
    expect(geminiRadio).toBeChecked()
  })

  it('renders the ModelPicker with an initial value', async () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    const {user} = render(<ModelPicker initialModelID="gemini-2.0-flash-001" />, {wrapper})

    const modelPicker = screen.getByTestId('model-picker')
    expect(modelPicker).toBeVisible()
    expect(modelPicker).toHaveTextContent('Gemini 2.0 Flash')

    const geminiButton = screen.getByRole('button', {name: 'Gemini 2.0 Flash'})
    await user.click(geminiButton) // Opens picker

    let menuItems = screen.getAllByRole('menuitemradio')
    expect(menuItems.length).toEqual(2)

    let gptRadio = screen.getByRole('menuitemradio', {name: 'GPT-4.1'})
    expect(gptRadio).toBeInTheDocument()
    expect(gptRadio).not.toBeChecked()
    let geminiRadio = screen.getByRole('menuitemradio', {name: 'Gemini 2.0 Flash'})
    expect(geminiRadio).toBeInTheDocument()
    expect(geminiRadio).toBeChecked()

    await user.click(gptRadio) // Picks GPT, closes picker

    expect(modelPicker).toHaveTextContent('GPT-4.1')

    const gptButton = screen.getByRole('button', {name: 'GPT-4.1'})
    await user.click(gptButton) // Opens picker

    menuItems = screen.getAllByRole('menuitemradio')
    expect(menuItems.length).toEqual(2)

    gptRadio = screen.getByRole('menuitemradio', {name: 'GPT-4.1'})
    expect(gptRadio).toBeInTheDocument()
    expect(gptRadio).toBeChecked()
    geminiRadio = screen.getByRole('menuitemradio', {name: 'Gemini 2.0 Flash'})
    expect(geminiRadio).toBeInTheDocument()
    expect(geminiRadio).not.toBeChecked()
  })
})
