import {render} from '@github-ui/react-core/test-utils'
import {TrashIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import {screen} from '@testing-library/react'

import {SimpleListItem} from '../components/SimpleListItem/SimpleListItem'
import {SimpleListView} from '../components/SimpleListView'

describe('SimpleListView component', () => {
  it('renders an item without crashing', () => {
    render(
      <SimpleListView data-testid="simple-list-view">
        <SimpleListItem>
          <SimpleListItem.Title>Item title</SimpleListItem.Title>
        </SimpleListItem>
      </SimpleListView>,
    )

    expect(screen.getByTestId('simple-list-view')).toBeInTheDocument()
  })

  it('renders an item w/ a description without crashing', () => {
    render(
      <SimpleListView data-testid="simple-list-view">
        <SimpleListItem>
          <SimpleListItem.Title>Item title</SimpleListItem.Title>
          <SimpleListItem.Description>This is an optional short description</SimpleListItem.Description>
        </SimpleListItem>
      </SimpleListView>,
    )

    expect(screen.getByTestId('simple-list-view')).toBeInTheDocument()
  })

  it('renders an item with a link', () => {
    render(
      <SimpleListView data-testid="simple-list-view">
        <SimpleListItem>
          <SimpleListItem.Title href="https://github.com">Linked item title</SimpleListItem.Title>
        </SimpleListItem>
      </SimpleListView>,
    )

    const link = screen.getByRole('link', {name: 'Linked item title'})
    expect(link).toHaveAttribute('href', 'https://github.com')
  })

  it('renders an item title with an action', () => {
    render(
      <SimpleListView data-testid="simple-list-view">
        <SimpleListItem>
          <SimpleListItem.Title onClick={jest.fn()}>Button item title</SimpleListItem.Title>
        </SimpleListItem>
      </SimpleListView>,
    )

    expect(screen.getByRole('button', {name: 'Button item title'})).toBeInTheDocument()
  })

  // This test relies on a computed style for link that is no longer calculated since styles from Primer React are not
  // applied in JSDOM. This test should be re-enabled once we have a way to test computed styles.
  it.skip("follows the user's a11y underline preference for the link item title", () => {
    document.documentElement.setAttribute('data-a11y-link-underlines', 'true')

    render(
      <SimpleListView data-testid="simple-list-view">
        <SimpleListItem>
          <SimpleListItem.Title href="#">Linked item title</SimpleListItem.Title>
        </SimpleListItem>
      </SimpleListView>,
    )

    const link = screen.getByRole('link')
    const linkStyle = window.getComputedStyle(link)
    expect(linkStyle.textDecoration).toContain('underline')
  })

  // This test relies on a computed style for link that is no longer calculated since styles from Primer React are not
  // applied in JSDOM. This test should be re-enabled once we have a way to test computed styles.
  it.skip('does not underline a link if a user has disabled a11y link underlines', () => {
    document.documentElement.setAttribute('data-a11y-link-underlines', 'false')

    render(
      <SimpleListView data-testid="simple-list-view">
        <SimpleListItem>
          <SimpleListItem.Title href="#">Linked item title</SimpleListItem.Title>
        </SimpleListItem>
      </SimpleListView>,
    )

    const link = screen.getByRole('link')
    const linkStyle = window.getComputedStyle(link)
    expect(linkStyle.textDecoration).not.toContain('underline')
  })

  describe('SimpleListItem.Button', () => {
    it('calls the onClick handler passed to the button control', async () => {
      const onClick = jest.fn()

      const {user} = render(
        <SimpleListView>
          <SimpleListItem>
            <SimpleListItem.Title>Button item</SimpleListItem.Title>
            <SimpleListItem.Actions>
              <Button onClick={onClick}>Button</Button>
            </SimpleListItem.Actions>
          </SimpleListItem>
        </SimpleListView>,
      )

      expect(onClick).not.toHaveBeenCalled()
      await user.click(screen.getByRole('button'))
      expect(onClick).toHaveBeenCalled()
    })
  })

  describe('SimpleListItem.Actions', () => {
    it('renders whatever element is passed to the actions', () => {
      render(
        <SimpleListView>
          <SimpleListItem>
            <SimpleListItem.Title>Action Menu item</SimpleListItem.Title>
            <SimpleListItem.Actions>
              <div data-testid="custom-control">Custom control</div>
            </SimpleListItem.Actions>
          </SimpleListItem>
        </SimpleListView>,
      )

      expect(screen.getByTestId('custom-control')).toBeInTheDocument()
    })
  })

  describe('SimpleListItem.TrailingActions', () => {
    it('renders whatever element is passed to the trailing actions', () => {
      render(
        <SimpleListView>
          <SimpleListItem>
            <SimpleListItem.Title>Action Menu item</SimpleListItem.Title>
            <SimpleListItem.TrailingActions>
              <IconButton data-testid="trash-icon-button" variant="danger" aria-label="Delete" icon={TrashIcon} />
            </SimpleListItem.TrailingActions>
          </SimpleListItem>
        </SimpleListView>,
      )

      expect(screen.getByTestId('trash-icon-button')).toBeInTheDocument()
    })
  })
})
