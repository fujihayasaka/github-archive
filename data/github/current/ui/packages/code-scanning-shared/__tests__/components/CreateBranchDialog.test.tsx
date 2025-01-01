import {act, screen, waitFor} from '@testing-library/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {CreateBranchDialog, type CreateBranchDialogProps} from '../../components/CreateBranchDialog'
import {RelayEnvironmentProvider, type Environment} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'
import {buildBranch} from '@github-ui/item-picker/test-utils/BranchPickerHelpers'
import type {CreateBranchResponse} from '../../hooks/use-create-branch-mutation'
import type {PullRequest} from '../../types/pull-request'

const createPath = '/github/security-campaigns/security/campaigns/1/branches'

const onClose = jest.fn()
let routeMock: jest.Mock

type TestWrapperProps = {
  children: React.ReactNode
}

const render = (
  props?: Partial<CreateBranchDialogProps>,
  environment: Environment = createRelayMockEnvironment().environment,
) =>
  reactRender(
    <CreateBranchDialog
      alertNumbers={[5, 7]}
      repository={{
        ownerLogin: 'monalisa',
        name: 'my-repo',
      }}
      createPath={createPath}
      onClose={onClose}
      someSelectedAlertsAreClosed={false}
      alertNumbersWithSuggestedFixes={[5, 7]}
      firstAlertWithSuggestedFixTitle="Code injection"
      branchType="new"
      isCampaign
      {...props}
    />,
    {
      wrapper: ({children}: TestWrapperProps) => {
        return <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      },
    },
  )

beforeEach(() => {
  routeMock = mockFetch.mockRoute(
    createPath,
    {
      branchName: 'branch-name',
      messages: [],
    },
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  onClose.mockReset()
})

it('renders button when no autofixes are available', async () => {
  render({alertNumbersWithSuggestedFixes: []})

  expect(screen.getByRole('dialog', {name: 'Create new branch'})).toBeInTheDocument()
  expect(
    screen.getByRole('button', {
      name: 'Create branch',
    }),
  ).toBeInTheDocument()
})

it('renders button when autofixes are available', async () => {
  render()

  expect(screen.getByRole('dialog', {name: 'Commit autofixes to new branch'})).toBeInTheDocument()
  expect(
    screen.getByRole('button', {
      name: 'Commit changes (2)',
    }),
  ).toBeInTheDocument()
})

it("renders button when autofixes are available and branchType is 'existing'", async () => {
  render({branchType: 'existing'})

  expect(screen.getByRole('dialog', {name: 'Commit autofixes to branch'})).toBeInTheDocument()
  expect(
    screen.getByRole('button', {
      name: 'Commit changes (2)',
    }),
  ).toBeInTheDocument()
})

it('renders option for opening a PR when no autofixes are available', async () => {
  render({alertNumbersWithSuggestedFixes: []})

  expect(screen.getByRole('dialog', {name: 'Create new branch'})).toBeInTheDocument()
  expect(screen.queryByRole('radio', {name: 'Open a pull request'})).not.toBeInTheDocument()
})

it('renders option for opening a PR when autofixes are available', async () => {
  render()

  expect(screen.getByRole('dialog', {name: 'Commit autofixes to new branch'})).toBeInTheDocument()
  expect(screen.getByRole('radio', {name: 'Open a pull request'})).toBeInTheDocument()
})

it("doesn't show the fixed/dismissed alert info flash when someSelectedAlertsAreClosed is false", async () => {
  render()

  expect(screen.queryByText('Closed and fixed alerts will not be included in this branch')).not.toBeInTheDocument()
})

it('shows the fixed/dismissed alert info flash when someSelectedAlertsAreClosed is true', async () => {
  render({someSelectedAlertsAreClosed: true})

  expect(screen.getByText('Closed and fixed alerts will not be included in this branch')).toBeInTheDocument()
})

it('can create a branch', async () => {
  const {user} = render()
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(routeMock).toHaveBeenCalledWith(
    createPath,
    expect.objectContaining({
      body: JSON.stringify({
        name: 'campaign-fix-5-7',
        alert_numbers: [5, 7],
        commit_autofix_suggestions: true,
        create_new_branch: true,
        create_draft_pr: true,
      }),
    }),
  )
  expect(onClose).toHaveBeenCalledWith('pr', 'branch-name', undefined, [])
  expect(button).not.toBeDisabled()
})

it('can create a branch with a different next step', async () => {
  const {user} = render()
  await user.click(
    screen.getByRole('radio', {
      name: 'Open branch with GitHub Desktop',
    }),
  )
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(onClose).toHaveBeenCalledWith('desktop', 'branch-name', undefined, [])
})

it('can create a branch with a name', async () => {
  const {user} = render()
  const textbox = screen.getByRole('textbox', {
    name: 'Branch name *',
  })
  await user.clear(textbox)
  await user.type(textbox, 'my-branch-name')
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(routeMock).toHaveBeenCalledWith(
    createPath,
    expect.objectContaining({
      body: JSON.stringify({
        name: 'my-branch-name',
        alert_numbers: [5, 7],
        commit_autofix_suggestions: true,
        create_new_branch: true,
        create_draft_pr: true,
      }),
    }),
  )
  expect(onClose).toHaveBeenCalledWith('pr', 'branch-name', undefined, [])
})

it('cannot create a branch without a name', async () => {
  const {user} = render()
  const textbox = screen.getByRole('textbox', {
    name: 'Branch name *',
  })
  await user.clear(textbox)
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })

  expect(button).toBeDisabled()
})

it('can create a branch with error messages', async () => {
  routeMock = mockFetch.mockRoute(
    createPath,
    {
      branchName: 'branch-name',
      messages: ['Failed to create commit'],
    },
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(onClose).toHaveBeenCalledWith('pr', 'branch-name', undefined, ['Failed to create commit'])
})

it('can add to an existing branch', async () => {
  const {environment} = createRelayMockEnvironment()
  const {user} = render({branchType: 'existing'}, environment)

  await act(async () => {
    environment.mock.resolveMostRecentOperation(operation =>
      MockPayloadGenerator.generate(operation, {
        RefConnection() {
          return {
            edges: [
              {node: buildBranch({id: 'b1', name: 'branch1'})},
              {node: buildBranch({id: 'b2', name: 'branch2'})},
              {node: buildBranch({id: 'b3', name: 'branch3'})},
            ],
          }
        },
      }),
    )
  })

  const button = screen.getByRole('button', {
    name: 'Select a branch',
  })

  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = screen.getByRole('option', {name: 'branch2'})
  await user.click(options)

  const submitButton = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })

  await user.click(submitButton)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(routeMock).toHaveBeenCalledWith(
    createPath,
    expect.objectContaining({
      body: JSON.stringify({
        name: 'branch2',
        alert_numbers: [5, 7],
        commit_autofix_suggestions: true,
        create_new_branch: false,
        create_draft_pr: true,
      }),
    }),
  )
  expect(onClose).toHaveBeenCalledWith('pr', 'branch-name', undefined, [])
})

it('can create a draft PR', async () => {
  const pullRequest: PullRequest = {
    repository: {
      ownerLogin: 'github',
      name: 'security-campaigns',
    },
    number: 1,
  }

  routeMock = mockFetch.mockRoute(
    createPath,
    {
      branchName: 'branch-name',
      pullRequest,
      messages: [],
    } satisfies CreateBranchResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()

  await user.click(
    screen.getByRole('radio', {
      name: 'Open a pull request',
    }),
  )

  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(routeMock).toHaveBeenCalledWith(
    createPath,
    expect.objectContaining({
      body: JSON.stringify({
        name: 'campaign-fix-5-7',
        alert_numbers: [5, 7],
        commit_autofix_suggestions: true,
        create_new_branch: true,
        create_draft_pr: true,
      }),
    }),
  )
  expect(onClose).toHaveBeenCalledWith('pr', 'branch-name', pullRequest, [])
  expect(button).toBeDisabled()
})

it('cannot add to an existing branch when no branch is selected', async () => {
  const {environment} = createRelayMockEnvironment()
  render({branchType: 'existing'}, environment)

  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })

  expect(button).toBeDisabled()
})

it('shows a 422 error when returned from the server', async () => {
  routeMock = mockFetch.mockRoute(
    createPath,
    {
      message: 'Branch already exists',
    },
    {
      ok: false,
      status: 422,
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  const {user} = render()
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(onClose).not.toHaveBeenCalled()
  expect(screen.getByText('Branch already exists')).toBeInTheDocument()
})

it('shows a 500 error when returned from the server', async () => {
  routeMock = mockFetch.mockRoute(createPath, '500 error', {
    ok: false,
    status: 500,
  })

  const {user} = render()
  const button = screen.getByRole('button', {
    name: 'Commit changes (2)',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(onClose).not.toHaveBeenCalled()
  expect(screen.getByText('Something went wrong')).toBeInTheDocument()
})

it('does not render commit message and extended description with multiple autofixes', async () => {
  expect(screen.queryByRole('textbox', {name: 'Commit message'})).not.toBeInTheDocument()
  expect(screen.queryByRole('textbox', {name: 'Extended description'})).not.toBeInTheDocument()
})

it('renders commit message and extended description if there is only 1 autofix', async () => {
  render({alertNumbers: [5], alertNumbersWithSuggestedFixes: [5]})

  expect(screen.getByRole('textbox', {name: 'Commit message'})).toBeInTheDocument()
  expect(screen.getByRole('textbox', {name: 'Commit message'})).toHaveValue(
    'Potential fix for code scanning alert no. 5: Code injection',
  )
  expect(screen.getByRole('textbox', {name: 'Extended description'})).toBeInTheDocument()
})

it('can create a branch with commit message and extended description if there is only 1 autofix', async () => {
  const {user} = render({
    alertNumbers: [5],
    alertNumbersWithSuggestedFixes: [5],
  })
  const commitMessageTextbox = screen.getByRole('textbox', {
    name: 'Commit message',
  })
  await user.clear(commitMessageTextbox)
  await user.type(commitMessageTextbox, 'my commit message')

  const extendedDescriptionTextbox = screen.getByRole('textbox', {
    name: 'Extended description',
  })
  await user.clear(extendedDescriptionTextbox)
  await user.type(extendedDescriptionTextbox, 'extended description')

  const button = screen.getByRole('button', {
    name: 'Commit change',
  })
  await user.click(button)

  expect(routeMock).toHaveBeenCalledTimes(1)
  expect(routeMock).toHaveBeenCalledWith(
    createPath,
    expect.objectContaining({
      body: JSON.stringify({
        name: 'campaign-fix-5',
        alert_numbers: [5],
        commit_autofix_suggestions: true,
        create_new_branch: true,
        create_draft_pr: true,
        commit_message: 'my commit message',
        extended_description: 'extended description',
      }),
    }),
  )
  expect(onClose).toHaveBeenCalledWith('pr', 'branch-name', undefined, [])
  expect(button).not.toBeDisabled()
})

it('does not render commit message if there are 2 alerts and 1 autofix', async () => {
  render({alertNumbers: [5, 7], alertNumbersWithSuggestedFixes: [5]})

  expect(screen.queryByRole('textbox', {name: 'Commit message'})).not.toBeInTheDocument()
  expect(screen.queryByRole('textbox', {name: 'Extended description'})).not.toBeInTheDocument()
})
