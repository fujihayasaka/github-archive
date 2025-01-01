import {DelistForm} from '../../actions/DelistForm'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act, waitFor} from '@testing-library/react'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {marketplaceActionPath} from '@github-ui/paths'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'

describe('DelistForm', () => {
  describe('When the user can administer the repository', () => {
    describe('When the action has a slug', () => {
      const action = mockActionListing({slug: 'action-slug'})

      it('Renders the form', () => {
        render(<DelistForm action={action} repoAdminableByViewer isDialogOpen onDialogClose={jest.fn()} />)

        expect(screen.getByTestId('delist-form')).toBeInTheDocument()
        expect(screen.getByTestId('delist-form')).toHaveAttribute(
          'action',
          marketplaceActionPath({slug: 'action-slug'}),
        )
        expect(screen.getByTestId('delist-form')).toHaveAttribute('method', 'post')
      })

      it('Renders hidden input to set the method to delete', () => {
        render(<DelistForm action={action} repoAdminableByViewer isDialogOpen onDialogClose={jest.fn()} />)

        expect(screen.getByTestId('hidden-delete')).toHaveAttribute('value', 'delete')
        expect(screen.getByTestId('hidden-delete')).toHaveAttribute('type', 'hidden')
        expect(screen.getByTestId('hidden-delete')).toHaveAttribute('name', '_method')
      })

      it('Renders the authenticity token hidden input', () => {
        render(<DelistForm action={action} repoAdminableByViewer isDialogOpen onDialogClose={jest.fn()} />)

        // eslint-disable-next-line github/authenticity-token
        expect(screen.getByTestId('hidden-authenticity-token')).toHaveAttribute('name', 'authenticity_token')
      })

      it('Renders the confirmation dialog when isDialogOpen is true', () => {
        render(<DelistForm action={action} repoAdminableByViewer isDialogOpen onDialogClose={jest.fn()} />)

        expect(screen.getByText('Delist action?')).toBeInTheDocument()
        expect(
          screen.getByText(
            'Are you sure you want to delist this action from the Marketplace? Note: It will still be installable as long as the repository is public.',
          ),
        ).toBeInTheDocument()
        expect(screen.getByRole('button', {name: 'Delist action'})).toBeInTheDocument()
      })

      it('Does not render the confirmation dialog when isDialogOpen is false', () => {
        render(<DelistForm action={action} repoAdminableByViewer isDialogOpen={false} onDialogClose={jest.fn()} />)

        expect(screen.queryByText('Delist action?')).not.toBeInTheDocument()
        expect(
          screen.queryByText(
            'Are you sure you want to delist this action from the Marketplace? Note: It will still be installable as long as the repository is public.',
          ),
        ).not.toBeInTheDocument()
        expect(screen.queryByRole('button', {name: 'Delist action'})).not.toBeInTheDocument()
      })

      it('Sends an event and submits the form when the confirmation dialog is confirmed', async () => {
        render(<DelistForm action={action} repoAdminableByViewer isDialogOpen onDialogClose={jest.fn()} />)

        const confirmButton = screen.getByRole('button', {name: 'Delist action'})

        // Add an event handler to prevent the form from actually submitting, while still allowing the event to be sent
        const mockSubmit = jest.fn(e => e.preventDefault())
        const form = screen.getByTestId('delist-form')
        form.addEventListener('submit', mockSubmit)

        act(() => {
          confirmButton.click()
        })

        await waitFor(() => expect(mockSubmit).toHaveBeenCalled())
        expectAnalyticsEvents({
          type: 'marketplace.action.delist',
          data: {
            repository_action_id: action.globalRelayId,
            source_url: `${window.location}`,
            location: 'actions#show',
          },
        })
      })
    })

    describe('When the action does not have a slug', () => {
      it('Does not render', () => {
        render(
          <DelistForm
            action={mockActionListing({slug: ''})}
            repoAdminableByViewer
            isDialogOpen
            onDialogClose={jest.fn()}
          />,
        )

        expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-authenticity-token')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-delete')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the user cannot administer the repository', () => {
    describe('When the action has a slug', () => {
      it('Does not render', () => {
        render(
          <DelistForm
            action={mockActionListing({slug: 'action-slug'})}
            repoAdminableByViewer={false}
            isDialogOpen
            onDialogClose={jest.fn()}
          />,
        )

        expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-authenticity-token')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-delete')).not.toBeInTheDocument()
      })
    })

    describe('When the action does not have a slug', () => {
      it('Does not render', () => {
        render(
          <DelistForm
            action={mockActionListing({slug: ''})}
            repoAdminableByViewer={false}
            isDialogOpen
            onDialogClose={jest.fn()}
          />,
        )

        expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-authenticity-token')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-delete')).not.toBeInTheDocument()
      })
    })
  })
})
