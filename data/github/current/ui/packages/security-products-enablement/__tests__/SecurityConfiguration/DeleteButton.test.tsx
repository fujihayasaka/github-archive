import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockFetch, expectMockFetchCalledTimes} from '@github-ui/mock-fetch'
import {editSecurityConfigurationsRoutePayload, getSecurityConfigurationsRoutePayload} from '../../test-utils/mock-data'
import App from '../../App'
import DeleteButton from '../../components/SecurityConfiguration/DeleteButton'
import {clearState, mockSetFlashMessage, dialogWrapper as wrapper} from '../test-helpers'

const routePayload = getSecurityConfigurationsRoutePayload()

const editPayload = editSecurityConfigurationsRoutePayload({
  defaultForNewPublicRepos: true,
  defaultForNewPrivateRepos: true,
})

function TestComponent() {
  return (
    <App>
      <DeleteButton
        securityConfiguration={editPayload.securityConfiguration}
        clearState={clearState}
        setFlashMessage={mockSetFlashMessage}
      />
    </App>
  )
}

describe('DeleteButton', () => {
  it('deletes an existing configuration', async () => {
    const {user} = render(<TestComponent />, {routePayload, wrapper})

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configuration/1/repositories_count', {
      repo_count: 1,
    })

    await user.click(screen.getByRole('button', {name: 'Delete configuration'}))

    await waitFor(() => {
      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/configuration/1/repositories_count',
        1,
      )
    })

    // Wait for the pop-up to appear
    const deleteConfigDialog = await screen.findByRole('dialog')

    expect(deleteConfigDialog).toBeInTheDocument()

    // Click the "Delete configuration" button in the pop-up
    const deleteButton = within(deleteConfigDialog).getByRole('button', {name: 'Delete configuration'})
    await user.click(deleteButton)

    await waitFor(() => {
      expectMockFetchCalledTimes('/organizations/github/settings/security_products/configurations/1', 1)
    })
  })

  it('shows pop up dialog when attempt to delete an existing configuration returns 422', async () => {
    const {user} = render(<TestComponent />, {routePayload, wrapper})

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configurations/1')

    mockFetch.mockRouteOnce('/organizations/github/settings/security_products/configuration/1/repositories_count', {
      repo_count: 1,
    })

    await user.click(screen.getByRole('button', {name: 'Delete configuration'}))

    await waitFor(() => {
      expectMockFetchCalledTimes(
        '/organizations/github/settings/security_products/configuration/1/repositories_count',
        1,
      )
    })

    // Wait for the pop-up to appear
    const deleteConfigDialog = await screen.findByRole('dialog')

    expect(deleteConfigDialog).toBeInTheDocument()

    mockFetch.mockRouteOnce(
      '/organizations/github/settings/security_products/configurations/1',
      {error: 'Another enablement event is in progress. Please try again later.'},
      {
        ok: false,
        status: 422,
      },
    )

    // Click the "Delete configuration" button in the pop-up
    await user.click(within(deleteConfigDialog).getByRole('button', {name: 'Delete configuration'}))

    // Wait for the pop-up to appear
    await screen.findByRole('dialog')

    const updateFailedDialog = screen.getByRole('dialog')

    expect(updateFailedDialog).toHaveTextContent(/Unable to update High Risk/)
    expect(updateFailedDialog).toHaveTextContent(/Another enablement event is in progress. Please try again later./)

    // Click the "Okay" button in the pop-up
    await user.click(within(updateFailedDialog).getByRole('button', {name: 'Okay'}))
  })
})
