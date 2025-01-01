/* eslint eslint-comments/no-use: off */

import {act, render, screen, within} from '@testing-library/react'

import type {EnabledFeatures} from '../../../../client/api/enabled-features/contracts'
import type {MemexItem} from '../../../../client/api/memex-items/contracts'
import {SingleSelectOptions} from '../../../../client/components/fields/single-select/single-select-options'
import {createColumnModel} from '../../../../client/models/column-model'
import type {StatusColumnModel} from '../../../../client/models/column-model/system/status'
import {DefaultColumns} from '../../../../mocks/mock-data'
import {InitialItems} from '../../../../stories/data-source'
import {createMockEnvironment} from '../../../create-mock-environment'
import {TestAppContainer} from '../../../test-app-wrapper'

// mock that tells use that the column is already loaded
const findLoadedFieldIdsMock = jest.fn()
jest.mock('../../../../client/state-providers/columns/use-find-loaded-field-ids', () => {
  return {__esModule: true, useFindLoadedFieldIds: () => ({findLoadedFieldIds: findLoadedFieldIdsMock})}
})

// mock empty query variables to avoid needing to mock useViews
jest.mock('../../../../client/state-providers/memex-items/queries/use-paginated-memex-items-query-variables', () => {
  return {__esModule: true, usePaginatedMemexItemsQueryVariables: () => ({})}
})

const getWrapper = (enabledFeatures: Array<EnabledFeatures>, items: Array<MemexItem>) => {
  const wrapper: React.ComponentType<React.PropsWithChildren> = ({children}) => {
    createMockEnvironment({
      jsonIslandData: {
        'memex-items-data': items,
        'memex-columns-data': DefaultColumns,
        'memex-enabled-features': enabledFeatures,
      },
    })
    return <TestAppContainer>{children}</TestAppContainer>
  }
  return wrapper
}

describe('SingleSelectFieldOptions', () => {
  it('displays confirmation dialog before deleting option used by items', async () => {
    const statusColumn = createColumnModel(DefaultColumns.find(c => c.id === 'Status')!) as StatusColumnModel
    findLoadedFieldIdsMock.mockReturnValue([statusColumn.id])
    render(<SingleSelectOptions column={statusColumn} />, {
      wrapper: getWrapper([], InitialItems),
    })

    const optionToDelete = statusColumn.settings.options[1]
    const itemsWithOption = InitialItems.filter(
      i =>
        i.memexProjectColumnValues.find(v => v.memexProjectColumnId === statusColumn.id)?.value?.id ===
        optionToDelete.id,
    )
    expect(itemsWithOption.length).toBeGreaterThanOrEqual(1)

    const rows = await screen.findAllByRole('listitem')
    const optionRow = rows[1]
    expect(optionRow).toHaveTextContent(optionToDelete.name)

    const menuButton = within(optionRow).getByTestId('single-select-item-menu-button')
    act(() => {
      menuButton.click()
    })
    const deleteButton = await screen.findByTestId('single-select-item-delete-button')
    act(() => {
      deleteButton.click()
    })
    const dialog = await screen.findByRole('alertdialog')
    expect(dialog).toHaveTextContent(
      `The option will be permanently deleted from ${itemsWithOption.length} items in this project.`,
    )
  })

  it('when memex_table_without_limits is enabled, displays confirmation dialog before deleting any option', async () => {
    const statusColumn = createColumnModel(DefaultColumns.find(c => c.id === 'Status')!) as StatusColumnModel
    findLoadedFieldIdsMock.mockReturnValue([])
    const items: Array<MemexItem> = []

    render(<SingleSelectOptions column={statusColumn} />, {
      wrapper: getWrapper(['memex_table_without_limits'], items),
    })

    const optionToDelete = statusColumn.settings.options[1]
    const itemsWithOption = items.filter(
      i =>
        i.memexProjectColumnValues.find(v => v.memexProjectColumnId === statusColumn.id)?.value?.id ===
        optionToDelete.id,
    )
    expect(itemsWithOption).toHaveLength(0)

    const rows = await screen.findAllByRole('listitem')
    const optionRow = rows[1]
    expect(optionRow).toHaveTextContent(optionToDelete.name)

    const menuButton = within(optionRow).getByTestId('single-select-item-menu-button')
    act(() => {
      menuButton.click()
    })
    const deleteButton = await screen.findByTestId('single-select-item-delete-button')
    act(() => {
      deleteButton.click()
    })
    const dialog = await screen.findByRole('alertdialog')
    expect(dialog).toHaveTextContent('Warning: The option will be permanently deleted from any items in this project.')
  })
})
