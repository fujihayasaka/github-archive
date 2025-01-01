import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import {ModelResponseFormat} from '../ModelResponseFormat'

jest.mock('@github-ui/react-core/use-feature-flag')

const handleResponseFormatChange = jest.fn().mockName('handleResponseFormatChange')
const handleJsonSchemaChange = jest.fn().mockName('handleJsonSchemaChange')

describe('ModelResponseFormat', () => {
  it('renders the response format toggle with text selected, without schema', () => {
    render(
      <ModelResponseFormat
        responseFormat="text"
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        supportsJsonSchema={false}
        onSinglePlaygroundView
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    expect(responseFormatGroup).toBeInTheDocument()

    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')
    expect(responseFormatRadioGroup).toHaveTextContent('Response format')

    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Text'})).toHaveAttribute('aria-checked', 'true')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'JSON'})).toHaveAttribute('aria-checked', 'false')
    expect(within(responseFormatRadioGroup).queryByRole('radio', {name: 'Schema'})).not.toBeInTheDocument()
  })

  it('renders the response format toggle with schema option', () => {
    render(
      <ModelResponseFormat
        responseFormat="json_schema"
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        supportsJsonSchema
        onSinglePlaygroundView
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    expect(responseFormatGroup).toBeInTheDocument()

    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')
    expect(responseFormatRadioGroup).toHaveTextContent('Response format')

    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Text'})).toHaveAttribute('aria-checked', 'false')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'JSON'})).toHaveAttribute('aria-checked', 'false')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Schema (edit)'})).toHaveAttribute(
      'aria-checked',
      'true',
    )
  })

  it('does not render schema option if onSinglePlaygroundView is false', () => {
    render(
      <ModelResponseFormat
        responseFormat="text"
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        supportsJsonSchema
        onSinglePlaygroundView={false}
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    expect(responseFormatGroup).toBeInTheDocument()

    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')
    expect(responseFormatRadioGroup).toHaveTextContent('Response format')

    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Text'})).toHaveAttribute('aria-checked', 'true')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'JSON'})).toHaveAttribute('aria-checked', 'false')
    expect(within(responseFormatRadioGroup).queryByRole('radio', {name: 'Schema'})).not.toBeInTheDocument()
  })

  it('triggers handleResponseFormatChange when toggling formats', async () => {
    const {user} = render(
      <ModelResponseFormat
        responseFormat="text"
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        supportsJsonSchema
        onSinglePlaygroundView
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')

    const button = within(responseFormatRadioGroup).getByRole('radio', {name: 'JSON'})
    await user.click(button)
    expect(handleResponseFormatChange).toHaveBeenCalledTimes(1)
  })

  it('opens JsonSchemaDialog when toggling format to Schema', async () => {
    const {user} = render(
      <ModelResponseFormat
        responseFormat="text"
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        supportsJsonSchema
        onSinglePlaygroundView
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')

    const button = within(responseFormatRadioGroup).getByRole('radio', {name: 'Schema'})
    await user.click(button)
    expect(handleResponseFormatChange).toHaveBeenCalled()

    expect(screen.getByRole('dialog', {name: 'JSON Schema'})).toBeInTheDocument()
  })

  it('opens JsonSchemaDialog even if Schema is already selected', async () => {
    const {user} = render(
      <ModelResponseFormat
        responseFormat="json_schema"
        handleResponseFormatChange={handleResponseFormatChange}
        jsonSchema='{"type": "object"}'
        handleJsonSchemaChange={handleJsonSchemaChange}
        supportsJsonSchema
        onSinglePlaygroundView
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')

    const button = within(responseFormatRadioGroup).getByRole('radio', {name: 'Schema (edit)'})
    await user.click(button)
    expect(handleResponseFormatChange).toHaveBeenCalled()

    const dialog = screen.getByRole('dialog', {name: 'JSON Schema'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByTestId('codemirror-editor')).toHaveTextContent('{"type": "object"}')
  })
})
