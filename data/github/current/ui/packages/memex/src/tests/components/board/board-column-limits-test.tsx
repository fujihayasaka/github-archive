import {render, screen, waitFor} from '@testing-library/react'
import {userEvent} from '@testing-library/user-event'

import type {MemexColumn} from '../../../client/api/columns/contracts/memex-column'
import {Role} from '../../../client/api/common-contracts'
import type {PageViewUpdateRequest, PageViewUpdateResponse} from '../../../client/api/view/contracts'
import {overrideDefaultPrivileges} from '../../../client/helpers/viewer-privileges'
import {put_updateView} from '../../../mocks/msw-responders/views'
import {seedJSONIsland} from '../../../mocks/server/mock-server'
import {viewFactory} from '../../factories/views/view-factory'
import {mswServer} from '../../msw-server'
import {buildGroupedItemsResponse} from '../../state-providers/memex-items/query-client-api/helpers'
import {setupBoardView} from '../../test-app-wrapper'
import {buildCardsWithStatusValues} from './board-test-helper'

function groupForStatus(status: string, columns: Array<MemexColumn>) {
  const metadata = columns.find(c => c.name === 'Status')?.settings?.options?.find(o => o.name === status)
  return {
    groupId: `${status}Id`,
    groupValue: status,
    groupMetadata: metadata,
  }
}

function stubPutUpdateView(response: PageViewUpdateResponse) {
  const stub = jest.fn<void, [PageViewUpdateRequest]>()

  const handler = put_updateView(body => {
    stub(body)
    return Promise.resolve(response)
  })

  mswServer.use(handler)
  return stub
}

describe('column limit update request', () => {
  function setupBasicBoard() {
    const {columns, items} = buildCardsWithStatusValues({Todo: 1})
    const {Board} = setupBoardView({columns, items, viewerPrivileges: overrideDefaultPrivileges({role: Role.Write})})

    seedJSONIsland('memex-enabled-features', ['memex_table_without_limits'])

    seedJSONIsland(
      'memex-paginated-items-data',
      buildGroupedItemsResponse({
        groups: [
          {
            ...groupForStatus('Todo', columns),
            items,
          },
        ],
      }),
    )

    const statusField = columns[2]
    expect(statusField.name).toEqual('Status')

    return {Board, statusField}
  }

  async function updateColumnLimit(newLimit: string) {
    const requestStub = stubPutUpdateView({view: viewFactory.build()})

    await userEvent.click(screen.getByRole('button', {name: 'Actions for column: Todo'}))
    await userEvent.click(screen.getByRole('menuitem', {name: 'Set limit'}))
    await userEvent.type(screen.getByTestId('column-limit-text-input'), newLimit)
    await userEvent.click(screen.getByRole('button', {name: /^Save control/}))
    await waitFor(() => expect(requestStub).toHaveBeenCalled())

    const requestBody = requestStub.mock.calls[0][0]
    return requestBody
  }

  it('sets the column limit using the ID of a single-select option', async () => {
    const {Board, statusField} = setupBasicBoard()
    const optionId = statusField.settings!.options![0].id
    render(<Board />)

    expect(screen.getByTestId('column-items-counter')).toHaveTextContent('1')

    const requestBody = await updateColumnLimit('3')

    expect(requestBody.view.layoutSettings.board?.columnLimits![statusField.databaseId]).toEqual({
      [optionId]: 3,
    })
    expect(screen.getByTestId('column-items-counter')).toHaveTextContent('1 / 3')
  })
})
