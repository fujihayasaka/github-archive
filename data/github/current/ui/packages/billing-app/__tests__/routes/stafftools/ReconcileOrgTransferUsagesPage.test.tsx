import {render, screen} from '@testing-library/react'
import {setupUserEvent} from '@github-ui/react-core/test-utils'
import ReconcileOrgTransferUsagesRoutePage from '../../../routes/stafftools/ReconcileOrgTransferUsagesPage'
const userEvent = setupUserEvent()

// Mock useRoutePayload to avoid payload dependency
jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: () => ({orgs: 'org1'}),
}))

describe('ReconcileOrgTransferUsagesRoutePage', () => {
  it('renders the form fields', () => {
    render(<ReconcileOrgTransferUsagesRoutePage />)
    expect(screen.getByLabelText(/Organization ID/i)).toBeInTheDocument()
    expect(screen.getByLabelText(/Source Enterprise Customer ID/i)).toBeInTheDocument()
    expect(screen.getByLabelText(/Destination Enterprise Customer ID/i)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: /submit/i})).toBeInTheDocument()
  })

  it('allows typing into the fields', async () => {
    render(<ReconcileOrgTransferUsagesRoutePage />)
    const orgInput = screen.getByLabelText(/Organization ID/i)
    const sourceInput = screen.getByLabelText(/Source Enterprise Customer ID/i)
    const destInput = screen.getByLabelText(/Destination Enterprise Customer ID/i)
    await userEvent.type(orgInput, '123')
    await userEvent.type(sourceInput, 'src-456')
    await userEvent.type(destInput, 'dst-789')
    expect(orgInput).toHaveValue('123')
    expect(sourceInput).toHaveValue('src-456')
    expect(destInput).toHaveValue('dst-789')
  })

  it('submits the form and shows success message', async () => {
    global.fetch = jest.fn().mockResolvedValue({ok: true, json: async () => ({})}) as unknown as typeof fetch
    render(<ReconcileOrgTransferUsagesRoutePage />)
    await userEvent.type(screen.getByLabelText(/Organization ID/i), '123')
    await userEvent.type(screen.getByLabelText(/Source Enterprise Customer ID/i), '456')
    await userEvent.type(screen.getByLabelText(/Destination Enterprise Customer ID/i), '789')
    await userEvent.click(screen.getByRole('button', {name: /submit/i}))
    expect(await screen.findByText(/Usages reconciled successfully/i)).toBeInTheDocument()
    // @ts-expect-error: cleaning up global.fetch after test
    global.fetch = undefined
  })

  it('shows error message if submission fails (response not ok)', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      json: async () => ({error: 'Custom error from backend'}),
    }) as unknown as typeof fetch
    render(<ReconcileOrgTransferUsagesRoutePage />)
    await userEvent.type(screen.getByLabelText(/Organization ID/i), '123')
    await userEvent.type(screen.getByLabelText(/Source Enterprise Customer ID/i), 'src-456')
    await userEvent.type(screen.getByLabelText(/Destination Enterprise Customer ID/i), 'dst-789')
    await userEvent.click(screen.getByRole('button', {name: /submit/i}))
    expect(await screen.findByText(/Custom error from backend/i)).toBeInTheDocument()
    // @ts-expect-error: cleaning up global.fetch after test
    global.fetch = undefined
  })

  it('shows error message if fetch throws', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('Network error')) as unknown as typeof fetch
    render(<ReconcileOrgTransferUsagesRoutePage />)
    await userEvent.type(screen.getByLabelText(/Organization ID/i), '123')
    await userEvent.type(screen.getByLabelText(/Source Enterprise Customer ID/i), 'src-456')
    await userEvent.type(screen.getByLabelText(/Destination Enterprise Customer ID/i), 'dst-789')
    await userEvent.click(screen.getByRole('button', {name: /submit/i}))
    expect(await screen.findByText(/Submission failed. Please try again./i)).toBeInTheDocument()
    // @ts-expect-error: cleaning up global.fetch after test
    global.fetch = undefined
  })
})
