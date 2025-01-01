import {ResourceList} from '../../sidebar-shared/ResourceList'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RepoIcon} from '@primer/octicons-react'

describe('ResourceList', () => {
  it('Renders link items that have a url', () => {
    render(
      <ResourceList
        linkItems={[
          {url: 'https://link1.com', component: RepoIcon, text: 'Link 1'},
          {url: 'https://link2.com', component: RepoIcon, text: 'Link 2'},
          {url: undefined, component: RepoIcon, text: 'Not renderable'},
        ]}
      />,
    )

    expect(screen.getByRole('link', {name: 'Link 1'})).toHaveAttribute('href', 'https://link1.com')
    expect(screen.getByRole('link', {name: 'Link 2'})).toHaveAttribute('href', 'https://link2.com')
    expect(screen.queryByRole('link', {name: 'Not renderable'})).not.toBeInTheDocument()
  })

  it('Renders danger items that have an onSelect function', () => {
    render(
      <ResourceList
        linkItems={[]}
        dangerItems={[
          {onSelect: jest.fn(), component: RepoIcon, text: 'Danger 1'},
          {onSelect: jest.fn(), component: RepoIcon, text: 'Danger 2'},
          {onSelect: undefined, component: RepoIcon, text: 'Not renderable'},
        ]}
      />,
    )

    expect(screen.getByText('Danger 1')).toBeInTheDocument()
    expect(screen.getByText('Danger 2')).toBeInTheDocument()
    expect(screen.queryByText('Not renderable')).not.toBeInTheDocument()
  })
})
