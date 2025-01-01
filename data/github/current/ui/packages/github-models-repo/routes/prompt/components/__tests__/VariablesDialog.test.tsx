import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {mockModel, mockResizeObserver} from '../../../../test-utils/mock-data'
import {VariablesDialog} from '../VariablesDialog'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

const onClose = jest.fn().mockName('onClose')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('VariablesDialog', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders when there are variables', async () => {
    const variables = {foo: 'bar', baz: 'qux'}
    const availableVariables = new Set(['foo', 'baz'])

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: false}}}),
    })

    const {user} = render(
      <VariablesDialog
        primaryTitle="Save Stuff"
        variables={variables}
        availableVariables={availableVariables}
        onClose={onClose}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Variables'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Variables'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const submitButton = within(dialog).getByRole('button', {name: 'Save Stuff ( control enter )'})
    expect(submitButton).toBeInTheDocument()
    expect(submitButton).toHaveAttribute('data-variant', 'primary')
    expect(submitButton).toBeEnabled()
    expect(within(dialog).getByRole('textbox', {name: '{{foo}}'})).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: '{{baz}}'})).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    expect(within(dialog).queryByRole('heading', {name: 'No variables'})).not.toBeInTheDocument()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('renders when there are no variables', async () => {
    const variables = {}
    const availableVariables = new Set<string>()
    const model = mockModel()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: true}}}),
    })

    render(
      <VariablesDialog
        primaryTitle="save"
        variables={variables}
        availableVariables={availableVariables}
        onClose={onClose}
        model={model}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Variables'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Variables'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const submitButton = within(dialog).getByRole('button', {name: 'save ( control enter )'})
    expect(submitButton).toBeInTheDocument()
    expect(submitButton).toHaveAttribute('data-variant', 'default')
    expect(submitButton).toBeDisabled()
    expect(within(dialog).queryByRole('textbox')).not.toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    expect(await within(dialog).findByRole('heading', {name: 'No variables'})).toBeInTheDocument()
    expect(
      within(dialog).getByText('You can add variables to the user and system prompts using the syntax.', {
        exact: false,
      }),
    ).toBeInTheDocument()
  })
})
