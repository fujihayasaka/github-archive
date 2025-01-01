import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {ComponentWithPreloadedQueryRef} from '@github-ui/relay-test-utils/RelayComponents'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import type {PreloadedQuery} from 'react-relay'
import {RelayEnvironmentProvider} from 'react-relay'
import {Suspense} from 'react'
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
}

function WrappedPaginatedOrganizationPicker({initialSelectedItemIds, queryRef}: WrapperPickerProps) {
  return (
    <PaginatedOrganizationPicker
      preloadedOrganizationsRef={queryRef}
      setSelectedItems={noop}
      initialSelectedItemIds={initialSelectedItemIds ?? []}
      selectionVariant={'single'}
    />
  )
}

type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  initialSelectedItemIds: string[]
}

function TestComponent({environment, initialSelectedItemIds}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <Suspense fallback="...Loading">
        <ComponentWithPreloadedQueryRef
          component={WrappedPaginatedOrganizationPicker}
          componentProps={{initialSelectedItemIds}}
          query={OrganizationPickerParentGraphqlQuery}
          queryVariables={{slug: 'github-inc', query: ''}}
        />
      </Suspense>
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
          const nodes = Array.from({length: 5}, (_, index) => ({
            id: `${index}`,
            login: `google-${index}`,
            avatarUrl: 'github.localhost',
          }))
          return {
            nodes,
            totalCount: nodes.length,
          }
        },
      })
    })

    render(<TestComponent environment={environment} initialSelectedItemIds={[]} />)
  }

  test('Shows the default state when empty', async () => {
    SetupAndRenderComponent()

    const button = screen.getByTestId('open-paginated-org-picker-dialog-button')
    expect(button).toBeInTheDocument()

    const organizationSelectedText = screen.queryByText(/0 selected/)
    expect(organizationSelectedText).toBeInTheDocument()
  })

  test('Renders single item select', async () => {
    SetupAndRenderComponent()

    const button = screen.getByTestId('open-paginated-org-picker-dialog-button')
    await userEvent.click(button)

    const checkBoxes = screen.getAllByRole('option')
    await userEvent.click(checkBoxes[0]!)

    const dialog = within(screen.getByRole('dialog'))
    expect(dialog.getByText('Next')).toBeInTheDocument()
    expect(dialog.getByText('Previous')).toBeInTheDocument()
    expect(dialog.getByText('Showing 1 of 5 organizations')).toBeInTheDocument()
    const submitButton = dialog.getByRole('button', {name: 'Select organization'})
    await userEvent.click(submitButton)

    expect(screen.getByText('1 selected')).toBeInTheDocument()
    const items = within(screen.getByRole('list')).getAllByRole('listitem')
    expect(items).toHaveLength(1)
  })
})
