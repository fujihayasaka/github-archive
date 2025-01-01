import {noop} from '@github-ui/noop'
import {CreateIssueButton} from '../CreateIssueButton'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockClientEnv} from '@github-ui/client-env/mock'

const navigateFn = jest.fn()

jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: () => navigateFn,
}))

jest.mock('../dialog/CreateIssueDialogEntry', () => {
  const CreateIssueDialogEntryMock = () => <p>dialog is open</p>
  return {CreateIssueDialogEntryInternal: CreateIssueDialogEntryMock}
})

describe('with logged in user', () => {
  beforeEach(() => {
    mockClientEnv({
      login: 'monalisa',
    })
  })

  test('it renders the button', () => {
    render(<CreateIssueButton label="New issue" navigate={noop} />)

    expect(screen.queryByRole('button', {name: 'New issue'})).toBeVisible()
  })

  test('it renders a link when there is a scoped repository', () => {
    render(
      <CreateIssueButton
        label="New issue"
        navigate={noop}
        optionConfig={{
          issueCreateArguments: {
            repository: {
              owner: 'github',
              name: 'issues',
            },
          },
        }}
      />,
    )

    const link = screen.queryByRole('link', {name: 'New issue'})
    expect(link).toBeVisible()
    expect(link).toHaveAttribute('href', '/github/issues/issues/new/choose')
  })

  test('it does not render a link when there is a no scoped repository', () => {
    render(<CreateIssueButton label="New issue" navigate={noop} />)

    expect(screen.queryByRole('link', {name: 'New issue'})).not.toBeInTheDocument()
  })

  test('it opens dialog on click when user is logged in without a scoped repository', async () => {
    const {user} = render(<CreateIssueButton label="New issue" navigate={noop} />)

    await user.click(screen.getByRole('button', {name: 'New issue'}))

    expect(screen.getByText('dialog is open')).toBeVisible()
    expect(navigateFn).not.toHaveBeenCalled()
  })

  test('it opens dialog on click when user is logged in with a scoped repository', async () => {
    const {user} = render(
      <CreateIssueButton
        label="New issue"
        navigate={noop}
        optionConfig={{
          issueCreateArguments: {
            repository: {
              owner: 'github',
              name: 'issues',
            },
          },
        }}
      />,
    )

    await user.click(screen.getByRole('link', {name: 'New issue'}))

    expect(screen.getByText('dialog is open')).toBeVisible()
    expect(navigateFn).not.toHaveBeenCalled()
  })

  test('it opens dialog on hotkey', async () => {
    const {user} = render(<CreateIssueButton label="New issue" navigate={noop} />)

    await user.keyboard('c')

    expect(screen.getByText('dialog is open')).toBeVisible()
  })
})

describe('with logged out user', () => {
  test('it renders the button', () => {
    render(<CreateIssueButton label="New issue" navigate={noop} />)

    const link = screen.queryByRole('link', {name: 'New issue'})
    expect(link).toHaveAttribute('href', '/login?return_to=http://localhost/')
    expect(link).toBeVisible()
  })

  test('it redirects to login page', async () => {
    const {user} = render(<CreateIssueButton label="New issue" navigate={noop} />)

    await user.click(screen.getByRole('link', {name: 'New issue'}))

    expect(screen.queryByText('dialog is open')).not.toBeInTheDocument()
    expect(navigateFn).toHaveBeenCalledWith('/login?return_to=http://localhost/')
  })

  test('it does not respond to hotkey', async () => {
    const {user} = render(<CreateIssueButton label="New issue" navigate={noop} />)

    await user.keyboard('c')

    expect(screen.queryByText('dialog is open')).not.toBeInTheDocument()
  })
})
