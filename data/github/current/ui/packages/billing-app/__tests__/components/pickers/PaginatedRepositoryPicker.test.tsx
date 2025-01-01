import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {ComponentWithPreloadedQueryRef} from '@github-ui/relay-test-utils/RelayComponents'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import type {PreloadedQuery} from 'react-relay'
import {RelayEnvironmentProvider} from 'react-relay'
import {noop} from '@github-ui/noop'
import {
  PaginatedRepositoryPicker,
  PaginatedRepositoryPickerParentGraphqlQuery,
} from '../../../components/pickers/PaginatedRepositoryPicker'
import type {PaginatedRepositoryPickerGraphqlQuery} from '../../../components/pickers/__generated__/PaginatedRepositoryPickerGraphqlQuery.graphql'
import type {GraphQLError} from '@github-ui/fetch-graphql'

const userEvent = setupUserEvent()

interface WrapperPickerProps {
  queryRef: PreloadedQuery<PaginatedRepositoryPickerGraphqlQuery>
  selectionVariant?: 'single' | 'multiple'
  initialSelectedItemIds?: string[]
}

function WrappedPaginatedRepositoryPicker({initialSelectedItemIds, queryRef, selectionVariant}: WrapperPickerProps) {
  return (
    <PaginatedRepositoryPicker
      preloadedRepositoriesRef={queryRef}
      setSelectedItems={noop}
      initialSelectedItemIds={initialSelectedItemIds ?? []}
      selectionVariant={selectionVariant ?? 'single'}
      slug="github-inc"
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
        component={WrappedPaginatedRepositoryPicker}
        componentProps={{initialSelectedItemIds, selectionVariant}}
        query={PaginatedRepositoryPickerParentGraphqlQuery}
        queryVariables={{slug: 'github-inc', phrase: ''}}
      />
    </RelayEnvironmentProvider>
  )
}

describe('PaginatedRepositoryPicker', () => {
  function SetupAndRenderComponent() {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(PaginatedRepositoryPickerParentGraphqlQuery, {
      slug: 'github-inc',
      phrase: '',
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [
              {node: {id: '1', nameWithOwner: 'github/one', isPrivate: true, isArchived: false}},
              {node: {id: '2', nameWithOwner: 'github/two', isPrivate: true, isArchived: false}},
              {node: {id: '3', nameWithOwner: 'github/three', isPrivate: true, isArchived: false}},
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

    expect(screen.getByText('Repositories')).toBeInTheDocument()
    expect(screen.getByText('Select repository')).toBeInTheDocument()
    expect(screen.getByText('0 selected')).toBeInTheDocument()

    const button = screen.getByRole('button', {name: 'Select repository'})
    await userEvent.click(button)

    const checkBoxes = screen.getAllByRole('option')
    expect(checkBoxes).toHaveLength(3)
    expect(screen.getByText('github/one')).toBeInTheDocument()
    expect(screen.getByText('github/two')).toBeInTheDocument()
    expect(screen.getByText('github/three')).toBeInTheDocument()

    await userEvent.click(checkBoxes[1]!)
    const dialog = within(screen.getByRole('dialog'))
    const submitButton = dialog.getByRole('button', {name: 'Select repository'})
    await userEvent.click(submitButton)

    expect(screen.getByText('1 selected')).toBeInTheDocument()
  })
})

describe('PaginatedRepositoryPicker with defined initialSelectedItemIds', () => {
  function SetupAndRenderComponent(initialSelectedItemIds: string[] = []) {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(PaginatedRepositoryPickerParentGraphqlQuery, {
      slug: 'github-inc',
      phrase: '',
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [
              {node: {id: '1', nameWithOwner: 'github/one', isPrivate: true, isArchived: false}},
              {node: {id: '2', nameWithOwner: 'github/two', isPrivate: true, isArchived: false}},
              {node: {id: '3', nameWithOwner: 'github/three', isPrivate: true, isArchived: false}},
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

    expect(screen.getByText('Repositories')).toBeInTheDocument()
    expect(screen.getByText('Select repositories')).toBeInTheDocument()
    expect(screen.getByText('2 selected')).toBeInTheDocument()

    const button = screen.getByRole('button', {name: 'Select repositories'})
    await userEvent.click(button)

    const checkBoxes = screen.getAllByRole('option')
    expect(checkBoxes).toHaveLength(3)
    expect(screen.getByText('github/one')).toBeInTheDocument()
    expect(screen.getByText('github/two')).toBeInTheDocument()
    expect(screen.getByText('github/three')).toBeInTheDocument()
  })
})

describe('PaginatedRepositoryPicker with insufficient permissions', () => {
  function SetupAndRenderComponent() {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(PaginatedRepositoryPickerParentGraphqlQuery, {
      slug: 'github-inc',
      phrase: '',
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [{node: {id: '1', nameWithOwner: 'github/one', isPrivate: true, isArchived: false}}],
            totalCount: 1,
          }
        },
      })
    })
    const gerror: GraphQLError = {type: 'GraphQLError', message: 'validation error', path: [0]}

    const MockError = new Error('Validation Error', {cause: [gerror]})
    environment.mock.queueOperationResolver(() => MockError)

    render(<TestComponent environment={environment} initialSelectedItemIds={['1']} selectionVariant="multiple" />)
  }

  test('Renders preselected item with insufficient permissions', async () => {
    SetupAndRenderComponent()

    jest.spyOn(console, 'error').mockImplementation()

    const button = screen.getByRole('button', {name: 'Select repositories'})
    expect(button).toBeInTheDocument()

    const repositorySelectedText = screen.queryByText(/1 selected/)
    expect(repositorySelectedText).toBeInTheDocument()
  })
})

describe('PaginatedRepositoryPicker with ResourcePaginator for selected items', () => {
  function SetupAndRenderComponent(initialSelectedItemIds: string[] = []) {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(PaginatedRepositoryPickerParentGraphqlQuery, {
      slug: 'github-inc',
      phrase: '',
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: Array.from({length: 15}, (_, index) => ({
              node: {
                id: `${index + 1}`,
                nameWithOwner: `github/${index + 1}`,
                isPrivate: true,
                isArchived: false,
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

    expect(screen.getByText('Repositories')).toBeInTheDocument()
    expect(screen.getByText('Select repositories')).toBeInTheDocument()
    expect(screen.getByText('11 selected')).toBeInTheDocument()
    expect(screen.getByTestId('pagination-wrapper')).toBeInTheDocument()
    expect(screen.getByTestId('pagination-page-text')).toBeInTheDocument()
    expect(screen.getByText('1-10 of 11')).toBeInTheDocument()
  })
})
