import type {PropertyDefinition} from '@github-ui/custom-properties-types'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {CustomPropertyValuesTableV2} from '../CustomPropertyValuesTableV2'
import {sampleDefinitions, sampleOrgSource} from './test-helpers'

const definitionsCount = sampleDefinitions.length

const propertyValuesMap = {
  ['contains_phi']: {propertyName: 'contains_phi', value: 'true', changed: false, mixed: false},
  ['data_sensitivity']: {propertyName: 'data_sensitivity', value: 'medium', changed: false, mixed: false},
  ['cost_center_id']: {propertyName: 'cost_center_id', value: 'asia', changed: true, mixed: false},
  ['enterprise_id']: {propertyName: 'enterprise_id', value: 'abc-123-834', changed: true, mixed: false},
}

const sampleProps = {
  definitions: sampleDefinitions,
  editableDefinitions: sampleDefinitions,
  propertyValuesMap,
  setPropertyValue: jest.fn(),
  revertPropertyValue: jest.fn(),
  showLockMessages: true,
  orgName: 'properties-game',
  showSummary: false,
}

const samplePropsWithError = {
  definitions: sampleDefinitions,
  editableDefinitions: sampleDefinitions,
  propertyValuesMap: {
    ...propertyValuesMap,
    ['notes']: {
      propertyName: 'notes',
      value: 'invalid🦦value',
      changed: true,
      mixed: false,
      error: 'Contains invalid characters: 🦦',
    },
  },
  setPropertyValue: jest.fn(),
  revertPropertyValue: jest.fn(),
  showLockMessages: true,
  orgName: 'properties-game',
  showSummary: false,
}

describe('CustomPropertyValuesEditor', () => {
  it('renders editable fields', () => {
    render(<CustomPropertyValuesTableV2 {...sampleProps} />)

    const rows = screen.getAllByTestId('property-row')
    expect(rows).toHaveLength(definitionsCount)

    expect(rows[0]).toHaveTextContent('contains_phi')
    expect(rows[0]).toHaveTextContent('Is this repository used to process Protected Health Data under HIPAA?')
    expect(rows[0]).toHaveTextContent('true')

    expect(rows[1]).toHaveTextContent('data_sensitivity')
    expect(rows[1]).toHaveTextContent(
      'Level of sensitivity of data processed by this repository once deployed. Refer to our data classification policy for details on determining classification levels.',
    )
    expect(rows[1]).toHaveTextContent('medium')

    expect(rows[2]).toHaveTextContent('cost_center_id')
    expect(rows[2]).toHaveTextContent('The department to which costs may be charged for accounting purposes.')
    expect(screen.getByLabelText('cost_center_id')).toHaveValue('asia')

    expect(rows[3]).toHaveTextContent('notes')
    expect(rows[3]).toHaveTextContent('Enter some notes if you want')
    expect(screen.getByLabelText('notes')).toHaveValue('')
  })

  it('associates validation error with string input when validation error present', async () => {
    const {user} = render(<CustomPropertyValuesTableV2 {...samplePropsWithError} />)

    const input = screen.getByLabelText('notes')
    await user.type(input, 'invalid🦦value')

    await expect(screen.findByText('Contains invalid characters: 🦦')).resolves.toBeInTheDocument()
    expect(input).toHaveAttribute('aria-describedby', 'notes-validation-error')
  })

  it('does not add aria-describedby to input when no validation error', async () => {
    render(<CustomPropertyValuesTableV2 {...sampleProps} />)

    const input = screen.getByLabelText('notes')
    expect(input).not.toHaveAttribute('aria-describedby')
  })

  it('renders readable fields', () => {
    render(<CustomPropertyValuesTableV2 {...sampleProps} editableDefinitions={[]} />)

    const rows = screen.getAllByTestId('property-row')
    expect(rows).toHaveLength(definitionsCount)

    expect(rows[0]).toHaveTextContent('contains_phi')
    expect(rows[0]).toHaveTextContent('Is this repository used to process Protected Health Data under HIPAA?')
    expect(rows[0]).toHaveTextContent('true')

    expect(rows[1]).toHaveTextContent('data_sensitivity')
    expect(rows[1]).toHaveTextContent(
      'Level of sensitivity of data processed by this repository once deployed. Refer to our data classification policy for details on determining classification levels.',
    )
    expect(rows[1]).toHaveTextContent('medium')

    expect(rows[2]).toHaveTextContent('cost_center_id')
    expect(rows[2]).toHaveTextContent('The department to which costs may be charged for accounting purposes.')
    expect(rows[2]).toHaveTextContent('asia')

    expect(rows[3]).toHaveTextContent('notes')
    expect(rows[3]).toHaveTextContent('Enter some notes if you want')
  })

  it("doesn't render the lockMessage", () => {
    render(<CustomPropertyValuesTableV2 {...sampleProps} editableDefinitions={[]} showLockMessages={false} />)

    const rows = screen.getAllByTestId('property-row')
    expect(rows).toHaveLength(definitionsCount)

    expect(rows[0]).toHaveTextContent('contains_phi')
    expect(rows[0]).toHaveTextContent('Is this repository used to process Protected Health Data under HIPAA?')
    expect(rows[0]).toHaveTextContent('true')
    expect(rows[0]).not.toHaveTextContent('Managed by properties-game')
  })

  it('renders undo button for property managed by org', async () => {
    const {user} = render(<CustomPropertyValuesTableV2 {...sampleProps} />)

    const dropdown = screen.getByLabelText('Open reset options for cost_center_id')

    expect(dropdown).toBeInTheDocument()
    await user.click(dropdown)
    expect(screen.getByText('Undo')).toBeInTheDocument()
    expect(screen.getByText('Reset to default')).toBeInTheDocument()
    expect(screen.getByText('Inherit the value defined by the organization')).toBeInTheDocument()
  })

  it('renders undo button for property managed by business', async () => {
    const {user} = render(<CustomPropertyValuesTableV2 {...sampleProps} />)

    const dropdown = screen.getByLabelText('Open reset options for enterprise_id')

    expect(dropdown).toBeInTheDocument()
    await user.click(dropdown)
    expect(screen.getByText('Undo')).toBeInTheDocument()
    expect(screen.getByText('Reset to default')).toBeInTheDocument()
    expect(screen.getByText('Inherit the value defined by the enterprise')).toBeInTheDocument()
  })

  it("doesn't render undo button if showUndo is false", async () => {
    const {user} = render(<CustomPropertyValuesTableV2 {...sampleProps} showUndo={false} />)

    const dropdown = screen.getByLabelText('Open reset options for cost_center_id')

    expect(dropdown).toBeInTheDocument()
    await user.click(dropdown)
    expect(screen.queryByText('Undo')).not.toBeInTheDocument()
    expect(screen.getByText('Reset to default')).toBeInTheDocument()
  })

  it('renders comma separated multiselect values when showing summary', async () => {
    const multiSelectDefinitionWithDefault: PropertyDefinition = {
      propertyName: 'mult-select-default',
      description: null,
      valueType: 'multi_select',
      required: false,
      defaultValue: ['one', 'two', 'three'],
      allowedValues: ['one', 'two', 'three'],
      valuesEditableBy: 'org_actors',
      regex: null,
      source: sampleOrgSource,
    }

    render(
      <CustomPropertyValuesTableV2
        {...sampleProps}
        definitions={[...sampleProps.definitions, multiSelectDefinitionWithDefault]}
        showSummary
      />,
    )

    expect(screen.getByText('Default (one, two, three)')).toBeInTheDocument()
  })
})
