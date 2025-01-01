import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {OperationDescriptor} from 'relay-runtime'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {TestIssueTypePickerComponent, buildIssueType} from '../test-utils/IssueTypePickerHelpers'
import {IssueTypePickerGraphqlQuery, type IssueType} from '../components/IssueTypePicker'

const typeA = buildIssueType({name: 'IssueTypeA', color: 'RED', description: ''})
const typeB = buildIssueType({name: 'IssueTypeB', description: '', color: 'GRAY'})
const typeC = buildIssueType({name: 'with ws', description: '', color: 'GRAY'})

test('render issue types when clicking the anchor', async () => {
  const environment = setupEnvironment()

  const {user} = render(<TestIssueTypePickerComponent environment={environment} shortcutEnabled readonly={false} />)

  const button = await screen.findByRole('button')
  await user.click(button)

  expect(screen.getAllByRole('option')).toHaveLength(3)

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('IssueTypeA')
  expect(options[1]).toHaveTextContent('IssueTypeB')
})

test('render issue types when pressing the shortcut', async () => {
  const environment = setupEnvironment()

  const {user} = render(<TestIssueTypePickerComponent environment={environment} shortcutEnabled readonly={false} />)

  await user.keyboard('t')

  expect(screen.getAllByRole('option')).toHaveLength(3)

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('IssueTypeA')
  expect(options[1]).toHaveTextContent('IssueTypeB')
})

test('can display readonly preselected issue type', async () => {
  const environment = setupEnvironment()

  const {user} = render(
    <TestIssueTypePickerComponent
      environment={environment}
      shortcutEnabled
      readonly
      preselectedIssueTypeName="My Type"
    />,
  )

  const button = await screen.findByRole('button')
  expect(button).toHaveTextContent('My Type')
  await user.click(button)

  expect(screen.queryAllByRole('option')).toHaveLength(0)
})

function setupEnvironment() {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(IssueTypePickerGraphqlQuery, {owner: 'github', repo: 'issues'})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('IssueTypePickerQuery')
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          issueTypes: {
            edges: [{node: typeA}, {node: typeB}, {node: typeC}],
          },
        }
      },
    })
  })

  return environment
}

test('renders with an item containing a whitespace is already selected', async () => {
  const environment = setupEnvironment()

  const {user} = render(
    <TestIssueTypePickerComponent
      environment={environment}
      shortcutEnabled
      readonly={false}
      issueTypeToken={'"with ws"'}
    />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  const options = screen.getAllByRole('option')

  expect(options).toHaveLength(3)

  for (let i = 0; i < options.length; i++) {
    const shouldBeSelected = options[i]?.textContent === 'with ws'
    expect(options[i]?.getAttribute('aria-selected')).toBe(shouldBeSelected ? 'true' : 'false')
  }
})

test('can filter issue types by name', async () => {
  const environment = setupEnvironment()

  const {user} = render(<TestIssueTypePickerComponent environment={environment} shortcutEnabled readonly={false} />)

  const button = await screen.findByRole('button')
  await user.click(button)

  expect(screen.getAllByRole('option')).toHaveLength(3)

  const input = screen.getByRole('combobox')
  await user.type(input, 'A')

  expect(screen.getAllByRole('option')).toHaveLength(1)
  expect(screen.getByRole('option')).toHaveTextContent('IssueTypeA')
})

test('has "no matches" message', async () => {
  const environment = setupEnvironment()

  const {user} = render(<TestIssueTypePickerComponent environment={environment} shortcutEnabled readonly={false} />)

  const button = await screen.findByRole('button')
  await user.click(button)

  expect(screen.getAllByRole('option')).toHaveLength(3)

  const input = screen.getByRole('combobox')
  await user.type(input, 'Z')

  expect(screen.getByText('No issue types were found')).toBeDefined()
})

test('does not clear out selection if it is filtered out', async () => {
  const environment = setupEnvironment()
  const onSelectionChange = jest.fn()

  const {user} = render(
    <TestIssueTypePickerComponent
      environment={environment}
      shortcutEnabled
      readonly={false}
      overrides={{
        activeIssueType: typeA as unknown as IssueType,
        onSelectionChange,
      }}
    />,
  )

  const button = await screen.findByRole('button')
  await user.click(button)

  const input = screen.getByRole('combobox')
  await user.type(input, 'Z')

  expect(screen.getByText('No issue types were found')).toBeDefined()

  await user.keyboard('[Escape]')
  expect(screen.queryByText('No issue types were found')).not.toBeInTheDocument()
  expect(onSelectionChange).not.toHaveBeenCalled()
})
