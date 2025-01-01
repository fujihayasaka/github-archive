import {render, screen, waitFor} from '@testing-library/react'
import {userEvent} from '@testing-library/user-event'

import type {PageViewUpdateRequest, PageViewUpdateResponse} from '../../../client/api/view/contracts'
import {put_updateView} from '../../../mocks/msw-responders/views'
import {viewFactory} from '../../factories/views/view-factory'
import {mswServer} from '../../msw-server'
import {setupPaginatedBoard} from './board-test-helper'

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
    const {Board, statusField} = setupPaginatedBoard()
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
