import {PermissionsInfo} from '../../../apps/transparency/PermissionsInfo'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('PermissionsInfo', () => {
  it('Renders a table row for public permissions when there are no permissions', () => {
    render(<PermissionsInfo permissionsData={[]} />)

    expect(screen.getByRole('cell', {name: 'User'})).toBeInTheDocument()
    expect(
      screen.getByRole('cell', {
        name: 'Read access to public repositories, public organization information, and public user profile data',
      }),
    ).toBeInTheDocument()
  })

  it('Renders table rows including public permissions when there are multiple permissions', () => {
    render(
      <PermissionsInfo
        permissionsData={[
          {scope: 'repository', permissionLevel: 'read', values: ['code']},
          {scope: 'organization', permissionLevel: 'write', values: ['members']},
          {scope: 'user', permissionLevel: 'admin', values: ['email']},
        ]}
      />,
    )

    expect(screen.getByRole('cell', {name: 'Repository'})).toBeInTheDocument()
    expect(screen.getByRole('cell', {name: 'Read access to code'})).toBeInTheDocument()
    expect(screen.getByRole('cell', {name: 'Organization'})).toBeInTheDocument()
    expect(screen.getByRole('cell', {name: 'Read and write access to members'})).toBeInTheDocument()
    expect(screen.getAllByRole('cell', {name: 'User'})).toHaveLength(2)
    expect(screen.getByRole('cell', {name: 'Admin access to email'})).toBeInTheDocument()
    expect(
      screen.getByRole('cell', {
        name: 'Read access to public repositories, public organization information, and public user profile data',
      }),
    ).toBeInTheDocument()
  })

  it('Renders extra text for repository permissions when there are repository permissions', () => {
    render(<PermissionsInfo permissionsData={[{scope: 'repository', permissionLevel: 'read', values: ['code']}]} />)

    expect(
      screen.getByText(
        'Repository permissions can be granted for all or selected repositories owned by the installing account.',
      ),
    ).toBeInTheDocument()
  })

  it('Does not render extra text for repository permissions when there are no repository permissions', () => {
    render(
      <PermissionsInfo permissionsData={[{scope: 'organization', permissionLevel: 'write', values: ['members']}]} />,
    )

    expect(
      screen.queryByText(
        'Repository permissions can be granted for all or selected repositories owned by the installing account.',
      ),
    ).not.toBeInTheDocument()
  })

  it('Renders single file permissions as a repository permission', () => {
    render(
      <PermissionsInfo
        permissionsData={[{scope: 'single file', permissionLevel: 'write', values: ['test.rb', 'something.yml']}]}
      />,
    )

    expect(screen.getByRole('cell', {name: 'Repository'})).toBeInTheDocument()
    const cell = screen.getByRole('cell', {name: /Read and write access to files located at/})
    expect(cell).toHaveTextContent('Read and write access to files located at test.rb, something.yml')
  })
})
