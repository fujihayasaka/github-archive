import {screen, waitFor} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {validateRegexPath} from '@github-ui/paths'
import type {RegisteredRuleSchemaComponent, SchemaField} from '../../../../types/rules-types'
import {RegexField} from '../RegexField'

const REGEX_FIELD: SchemaField = {
  name: 'test_field',
  display_name: 'Test Field',
  description: 'Test description',
  required: true,
  ui_control: 'regex_pattern',
  default_value: '',
  type: 'string',
  beta: false,
}

const DEFAULT_PROPS: RegisteredRuleSchemaComponent = {
  field: REGEX_FIELD,
  value: '',
  sourceType: 'enterprise',
  onValueChange: jest.fn(),
  errors: [],
}

beforeEach(() => {
  jest.clearAllMocks()
})

const userEvent = setupUserEvent()

describe('RegexField', () => {
  test('it should render', async () => {
    render(<RegexField {...DEFAULT_PROPS} />)

    const patternInput = await screen.findByTestId('regex-field-pattern')

    expect(screen.getByText(REGEX_FIELD.description)).toBeInTheDocument()
    expect(screen.getByText(REGEX_FIELD.display_name)).toBeInTheDocument()
    expect(screen.queryByText('Invalid pattern')).not.toBeInTheDocument()
    expect(patternInput).toHaveAttribute('aria-invalid', 'false')
  })
  test('it should short circuit the API call if pattern is empty', async () => {
    render(<RegexField {...DEFAULT_PROPS} />)

    expect(mockFetch.fetch).not.toHaveBeenCalled()

    const patternInput = await screen.findByTestId('regex-field-pattern')
    await userEvent.type(patternInput, 'Sample code')
    await userEvent.clear(patternInput)
    await userEvent.tab()

    expect(mockFetch.fetch).not.toHaveBeenCalled()
    expect(patternInput).toHaveAttribute('aria-invalid', 'false')
  })
  test('it should call out to the validation API when the pattern changes', async () => {
    render(<RegexField {...DEFAULT_PROPS} value=".+" />)

    expect(mockFetch.fetch).not.toHaveBeenCalled()

    const patternInput = await screen.findByTestId('regex-field-pattern')
    await userEvent.type(patternInput, 'Sample code')
    await userEvent.tab()

    expect(DEFAULT_PROPS.onValueChange).toHaveBeenCalledTimes('Sample code'.length)
    await waitFor(() => {
      expect(mockFetch.fetch).toHaveBeenCalledTimes(1)
    })
    expect(patternInput).toHaveAttribute('aria-invalid', 'false')
  })

  test('it should show an error if the API returns invalid', async () => {
    render(<RegexField {...DEFAULT_PROPS} value=".+" />)

    mockFetch.mockRouteOnce(validateRegexPath(), {})
    expect(screen.queryByText('Invalid pattern')).not.toBeInTheDocument()

    const patternInput = await screen.findByTestId('regex-field-pattern')
    await userEvent.type(patternInput, 'Sample code')
    await userEvent.tab()

    mockFetch.resolvePendingRequest(`${validateRegexPath()}/pattern`, {}, {ok: false, status: 400})

    await waitFor(() => {
      expect(screen.getByText('Invalid pattern')).toBeInTheDocument()
    })
    expect(patternInput).toHaveAttribute('aria-invalid', 'true')
  })

  test('it should show an error if provided', async () => {
    render(<RegexField {...DEFAULT_PROPS} errors={[{error_code: '', message: 'Test error'}]} />)

    const patternInput = await screen.findByTestId('regex-field-pattern')
    expect(screen.getByText('Test error')).toBeInTheDocument()
    expect(patternInput).toHaveAttribute('aria-invalid', 'true')
  })
})
