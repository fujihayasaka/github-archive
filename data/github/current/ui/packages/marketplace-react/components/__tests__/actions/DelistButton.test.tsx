import {DelistButton} from '../../actions/DelistButton'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockActionListing} from '@github-ui/marketplace-common/mock-data'
import {mockDelistActionData} from '../../../test-utils/mock-data'
import {marketplaceActionPath} from '@github-ui/paths'

describe('DelistButton', () => {
  describe('When the user can administer the repository', () => {
    describe('When the action has a slug', () => {
      const action = mockActionListing({slug: 'action-slug'})
      const delistData = mockDelistActionData({repoAdminableByViewer: true, hydroAttrs: {foo: 'bar', hello: 'world'}})

      it('Renders the form', () => {
        render(<DelistButton action={action} delistActionData={delistData} />)

        expect(screen.getByTestId('delist-form')).toBeInTheDocument()
        expect(screen.getByTestId('delist-form')).toHaveAttribute(
          'action',
          marketplaceActionPath({slug: 'action-slug'}),
        )
        expect(screen.getByTestId('delist-form')).toHaveAttribute('method', 'post')
      })

      it('Renders hidden input to set the method to delete', () => {
        render(<DelistButton action={action} delistActionData={delistData} />)

        expect(screen.getByTestId('hidden-delete')).toHaveAttribute('value', 'delete')
        expect(screen.getByTestId('hidden-delete')).toHaveAttribute('type', 'hidden')
        expect(screen.getByTestId('hidden-delete')).toHaveAttribute('name', '_method')
      })

      it('Renders the delist button', () => {
        render(<DelistButton action={action} delistActionData={delistData} />)

        expect(screen.getByTestId('delist-button')).toHaveAttribute('type', 'submit')
      })

      it('Renders the delist button with the default data attributes', () => {
        render(<DelistButton action={action} delistActionData={delistData} />)

        expect(screen.getByTestId('delist-button')).toHaveAttribute(
          'data-confirm',
          'Are you sure you want to delist this Action from the Marketplace? Note: This Action will still be installable as long as the repository is public.',
        )
        expect(screen.getByTestId('delist-button')).toHaveAttribute('data-disable-with', 'Delisting...')
      })

      it('Renders the delist button with the hydro data attributes', () => {
        render(<DelistButton action={action} delistActionData={delistData} />)

        expect(screen.getByTestId('delist-button')).toHaveAttribute('data-foo', 'bar')
        expect(screen.getByTestId('delist-button')).toHaveAttribute('data-hello', 'world')
      })

      it('Renders the authenticity token hidden input', () => {
        render(<DelistButton action={action} delistActionData={delistData} />)

        // eslint-disable-next-line github/authenticity-token
        expect(screen.getByTestId('hidden-authenticity-token')).toHaveAttribute('name', 'authenticity_token')
      })
    })

    describe('When the action does not have a slug', () => {
      it('Does not render', () => {
        render(<DelistButton action={mockActionListing({slug: ''})} delistActionData={mockDelistActionData()} />)

        expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        expect(screen.queryByTestId('delist-button')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-authenticity-token')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-delete')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the user cannot administer the repository', () => {
    describe('When the action has a slug', () => {
      it('Does not render', () => {
        render(
          <DelistButton
            action={mockActionListing({slug: 'action-slug'})}
            delistActionData={mockDelistActionData({repoAdminableByViewer: false})}
          />,
        )

        expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        expect(screen.queryByTestId('delist-button')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-authenticity-token')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-delete')).not.toBeInTheDocument()
      })
    })

    describe('When the action does not have a slug', () => {
      it('Does not render', () => {
        render(
          <DelistButton
            action={mockActionListing({slug: ''})}
            delistActionData={mockDelistActionData({repoAdminableByViewer: false})}
          />,
        )

        expect(screen.queryByTestId('delist-form')).not.toBeInTheDocument()
        expect(screen.queryByTestId('delist-button')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-authenticity-token')).not.toBeInTheDocument()
        expect(screen.queryByTestId('hidden-delete')).not.toBeInTheDocument()
      })
    })
  })
})
