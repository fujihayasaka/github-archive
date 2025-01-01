import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {ComponentWithPreloadedQueryRef} from '@github-ui/relay-test-utils/RelayComponents'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import type {PreloadedQuery} from 'react-relay'
import {RelayEnvironmentProvider} from 'react-relay'
import {noop} from '@github-ui/noop'
import {
  PaginatedOrganizationPicker,
  OrganizationPickerParentGraphqlQuery,
} from '../../../components/pickers/PaginatedOrganizationPicker'
import type {PaginatedOrganizationPickerGraphqlQuery} from '../../../components/pickers/__generated__/PaginatedOrganizationPickerGraphqlQuery.graphql'

const userEvent = setupUserEvent()

interface WrapperPickerProps {
  queryRef: PreloadedQuery<PaginatedOrganizationPickerGraphqlQuery>
  initialSelectedItemIds?: string[]
  selectionVariant?: 'single' | 'multiple'
}

function WrappedPaginatedOrganizationPicker({initialSelectedItemIds, queryRef, selectionVariant}: WrapperPickerProps) {
  return (
    <PaginatedOrganizationPicker
      preloadedOrganizationsRef={queryRef}
      setSelectedItems={noop}
      initialSelectedItemIds={initialSelectedItemIds ?? []}
      selectionVariant={selectionVariant}
    />
  )
}

type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  initialSelectedItemIds: string[]
  selectionVariant?: 'single' | 'multiple'
}

function TestComponent({environment, initialSelectedItemIds, selectionVariant}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <ComponentWithPreloadedQueryRef
        component={WrappedPaginatedOrganizationPicker}
        componentProps={{initialSelectedItemIds, selectionVariant}}
        query={OrganizationPickerParentGraphqlQuery}
        queryVariables={{slug: 'github-inc', query: ''}}
      />
    </RelayEnvironmentProvider>
  )
}

describe('PaginatedOrganizationPicker tests for creation', () => {
  function SetupAndRenderComponent() {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(OrganizationPickerParentGraphqlQuery, {slug: 'github-inc', query: ''})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        OrganizationConnection() {
          return {
            edges: [
              {node: {id: '1', login: 'google-1', avatarUrl: 'localhost:3000/1.png'}},
              {node: {id: '2', login: 'google-2', avatarUrl: 'localhost:3000/2.png'}},
              {node: {id: '3', login: 'google-3', avatarUrl: 'localhost:3000/3.png'}},
            ],
            totalCount: 3,
          }
        },
      })
    })

    render(<TestComponent environment={environment} initialSelectedItemIds={[]} selectionVariant={'single'} />)
  }

  test('Renders single item select', async () => {
    SetupAndRenderComponent()

    expect(screen.getByText('Organizations')).toBeInTheDocument()
    expect(screen.getByText('Select organization')).toBeInTheDocument()
    expect(screen.getByText('0 selected')).toBeInTheDocument()

    const button = screen.getByRole('button', {name: 'Select organization'})
    await userEvent.click(button)

    const checkBoxes = screen.getAllByRole('option')
    expect(checkBoxes).toHaveLength(3)
    expect(screen.getByText('google-1')).toBeInTheDocument()
    expect(screen.getByText('google-2')).toBeInTheDocument()
    expect(screen.getByText('google-3')).toBeInTheDocument()

    await userEvent.click(checkBoxes[1]!)
    const dialog = within(screen.getByRole('dialog'))
    const submitButton = dialog.getByRole('button', {name: 'Select organization'})
    await userEvent.click(submitButton)

    expect(screen.getByText('1 selected')).toBeInTheDocument()
  })
})

describe('PaginatedOrganizationPicker with defined initialSelectedItemIds', () => {
  function SetupAndRenderComponent(initialSelectedItemIds: string[] = []) {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(OrganizationPickerParentGraphqlQuery, {slug: 'github-inc', query: ''})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        OrganizationConnection() {
          return {
            edges: [
              {node: {id: '1', login: 'google-1', avatarUrl: 'localhost:3000/1.png'}},
              {node: {id: '2', login: 'google-2', avatarUrl: 'localhost:3000/2.png'}},
              {node: {id: '3', login: 'google-3', avatarUrl: 'localhost:3000/3.png'}},
            ],
            totalCount: 3,
          }
        },
      })
    })

    render(
      <TestComponent
        environment={environment}
        initialSelectedItemIds={initialSelectedItemIds}
        selectionVariant="multiple"
      />,
    )
  }

  test('Renders multiple selected items', async () => {
    SetupAndRenderComponent(['2', '3'])

    expect(screen.getByText('Organizations')).toBeInTheDocument()
    expect(screen.getByText('Select organizations')).toBeInTheDocument()
    expect(screen.getByText('2 selected')).toBeInTheDocument()
    expect(screen.queryByTestId('pagination-wrapper')).not.toBeInTheDocument()

    const button = screen.getByRole('button', {name: 'Select organizations'})
    await userEvent.click(button)

    const checkBoxes = screen.getAllByRole('option')
    expect(checkBoxes).toHaveLength(3)
    expect(screen.getByText('google-1')).toBeInTheDocument()
    expect(screen.getByText('google-2')).toBeInTheDocument()
    expect(screen.getByText('google-3')).toBeInTheDocument()
  })
})

describe('PaginatedOrganizationPicker with ResourcePaginator for selected items', () => {
  function SetupAndRenderComponent(initialSelectedItemIds: string[] = []) {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(OrganizationPickerParentGraphqlQuery, {slug: 'github-inc', query: ''})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        OrganizationConnection() {
          return {
            edges: Array.from({length: 15}, (_, index) => ({
              node: {
                id: `${index + 1}`,
                login: `google-${index + 1}`,
                avatarUrl: `localhost:3000/${index + 1}.png`,
              },
            })),
            totalCount: 15,
          }
        },
      })
    })

    render(
      <TestComponent
        environment={environment}
        initialSelectedItemIds={initialSelectedItemIds}
        selectionVariant="multiple"
      />,
    )
  }

  test('Renders multiple selected items', async () => {
    SetupAndRenderComponent(Array.from({length: 11}, (_, index) => `${index + 1}`))

    expect(screen.getByText('Organizations')).toBeInTheDocument()
    expect(screen.getByText('Select organizations')).toBeInTheDocument()
    expect(screen.getByText('11 selected')).toBeInTheDocument()
    expect(screen.getByTestId('pagination-wrapper')).toBeInTheDocument()
    expect(screen.getByTestId('pagination-page-text')).toBeInTheDocument()
    expect(screen.getByText('1-10 of 11')).toBeInTheDocument()
  })
})
