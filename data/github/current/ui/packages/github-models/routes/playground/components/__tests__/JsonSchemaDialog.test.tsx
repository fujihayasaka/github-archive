import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {act} from 'react'

import {JsonSchemaDialog} from '../JsonSchemaDialog'
import {JSON_SCHEMA_DOCS_URL} from '../constants'

const onClose = jest.fn().mockName('onClose')
const onSubmit = jest.fn().mockName('onSubmit')
const jsonSchema = '{"type": "object", "properties": {"name": {"type": "string"}}}'

describe('JsonSchemaDialog', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('loads JsonSchemaDialog with banner to use sample if jsonSchema is empty', async () => {
    await render(<JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema="" />)

    const dialog = screen.getByRole('dialog', {name: 'JSON Schema'})
    expect(dialog).toBeInTheDocument()

    const bannerMessage = within(dialog).getByText(/No JSON schema saved/i)
    expect(bannerMessage).toBeInTheDocument()

    // There will always be two buttons rendered in the HTML, depending on viewport size, only one will be visible each time
    const useSampleSchemaButton = within(dialog).getAllByRole('button', {
      name: 'Use sample',
    })[0] as HTMLButtonElement
    expect(useSampleSchemaButton).toBeInTheDocument()
  })

  it('loads JsonSchemaDialog with JSON Schema and code mirror containing jsonSchema', async () => {
    await render(<JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema={jsonSchema} />)

    const dialog = screen.getByRole('dialog', {name: 'JSON Schema'})
    expect(dialog).toBeInTheDocument()

    const codeMirrorEditorEl = within(dialog).getByTestId('codemirror-editor')
    expect(codeMirrorEditorEl).toHaveTextContent(jsonSchema)
  })

  it('loads JsonSchemaDialog with Cancel and Save footer buttons', async () => {
    await render(<JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema="" />)

    const dialog = screen.getByRole('dialog', {name: 'JSON Schema'})

    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Save'})).toBeInTheDocument()
  })

  it('calls onClose when Cancel button is clicked', async () => {
    const {user} = await render(<JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema={jsonSchema} />)

    const cancelButton = await screen.findByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('calls onSubmit when Save button is clicked for valid JSON', async () => {
    const {user} = await render(<JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema={jsonSchema} />)

    const saveButton = screen.getByRole('button', {name: 'Save'})
    await user.click(saveButton)

    expect(onSubmit).toHaveBeenCalledTimes(1)
  })

  it('shows an error when Save button is clicked for invalid JSON', async () => {
    const invalidJsonSchema = 'hello'
    const {user} = await render(
      <JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema={invalidJsonSchema} />,
    )

    const saveButton = screen.getByRole('button', {name: 'Save'})
    await user.click(saveButton)

    const errorMessage = screen.getByText(/Invalid JSON schema provided/i)
    expect(errorMessage).toBeInTheDocument()
  })

  it('provides a link to docs in the subtitle', async () => {
    await render(<JsonSchemaDialog onClose={onClose} onSubmit={onSubmit} jsonSchema={jsonSchema} />)

    expect(screen.getByRole('link', {name: 'JSON schema'})).toHaveAttribute('href', JSON_SCHEMA_DOCS_URL)
  })
})

async function render(component: JSX.Element) {
  // Need the `act` call to avoid a warning about "A suspended resource finished loading inside a test, but the
  // event was not wrapped in act" due to `Suspense` being used in JsonSchemaDialog.
  // eslint-disable-next-line testing-library/no-unnecessary-act
  return await act(async () => {
    return htmlRender(component)
  })
}
