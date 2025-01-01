import {act, screen, waitFor, within} from '@testing-library/react'
import {render as reactRender, type User} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {TestWrapper} from '@github-ui/security-campaigns-shared/test-utils/TestWrapper'
import {createRepository, createSecurityCampaignAlert} from '../../test-utils/mock-data'
import {RepoAlertsList, type RepoAlertsListProps} from '../../components/RepoAlertsList'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {type Environment, RelayEnvironmentProvider} from 'react-relay'

beforeAll(() => {
  performance.clearResourceTimings = jest.fn()
  performance.mark = jest.fn()
})

jest.setTimeout(10_000)

const openAlerts = [
  createSecurityCampaignAlert({
    number: 123,
    isFixed: false,
    isDismissed: false,
  }),
]
const openAlertsWithFixes = [
  createSecurityCampaignAlert({
    number: 151,
    isFixed: false,
    isDismissed: false,
    hasSuggestedFix: true,
  }),
]
const openAlertsPageTwo = [
  createSecurityCampaignAlert({
    number: 235,
    isFixed: false,
    isDismissed: false,
  }),
]
const closedAlerts = [
  createSecurityCampaignAlert({
    number: 783,
    isFixed: false,
    isDismissed: true,
  }),
]

function defaultGetAlertsResponse(props?: Partial<GetAlertsResponse>): GetAlertsResponse {
  return {
    alerts: openAlerts,
    openCount: openAlerts.length + openAlertsPageTwo.length,
    closedCount: closedAlerts.length,
    openWithLinksCount: 0,
    nextCursor: 'cursornext',
    prevCursor: '',
    ...props,
  }
}

const mockCreateBranch = () => {
  const createBranchPath = '/github/security-campaigns/security/campaigns/1/branches'
  mockFetch.mockRoute(
    createBranchPath,
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
}

const alertsPath = '/github/security-campaigns/security/campaigns/1/alerts'
type TestWrapperProps = {
  children: React.ReactNode
}

const render = async (
  props: Partial<RepoAlertsListProps> = {},
  environment: Environment = createRelayMockEnvironment().environment,
) => {
  const view = reactRender(
    <RepoAlertsList
      alertsPath={alertsPath}
      repository={createRepository()}
      createBranchPath="/github/security-campaigns/security/campaigns/1/branches"
      closeAlertsPath="/github/security-campaigns/security/campaigns/1/alerts"
      {...props}
    />,
    {
      wrapper: ({children}: TestWrapperProps) => {
        return (
          <RelayEnvironmentProvider environment={environment}>
            <TestWrapper>{children}</TestWrapper>
          </RelayEnvironmentProvider>
        )
      },
    },
  )

  // Wait for the alerts to load
  await waitFor(() => {
    expect(
      screen.getByRole('list', {
        name: `${defaultGetAlertsResponse().openCount + defaultGetAlertsResponse().closedCount} alerts`,
      }),
    ).toBeInTheDocument()
  })

  return view
}

const getActionByName = async (user: User, actionName: string) => {
  // In very rare cases, some actions which are usually visible get collapsed
  // to the overflow menu. This will open the overflow menu to ensure that the
  // action can still be found.
  const moreActionsButton = screen.queryByRole('button', {
    name: 'More Actions',
  })
  if (moreActionsButton) {
    await user.click(moreActionsButton)
  }

  return await screen.findByRole('button', {
    name: actionName,
  })
}

const mockOpenAlertsRoute = (props?: Partial<GetAlertsResponse>) => {
  return mockFetch.mockRoute(`${alertsPath}?query=${encodeURIComponent('is:open')}`, defaultGetAlertsResponse(props), {
    headers: new Headers({
      'Content-Type': 'application/json',
    }),
  })
}

it('renders', async () => {
  mockOpenAlertsRoute()

  await render()
  const list = await screen.findByRole('list', {
    name: '3 alerts',
  })
  expect(await within(list).findAllByRole('listitem')).toHaveLength(1)
  expect(await within(list).findAllByRole('link')).toHaveLength(1)
  expect(await within(list).findByText(/^#123/)).toBeInTheDocument()
})

it('can view closed alerts', async () => {
  mockOpenAlertsRoute()
  const {user} = await render()

  const mock = mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent('is:closed')}`,
    {
      ...defaultGetAlertsResponse(),
      alerts: closedAlerts,
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(
    await screen.findByRole('link', {
      name: /^Closed/,
    }),
  )

  const list = await screen.findByRole('list', {
    name: '3 alerts',
  })
  expect(await within(list).findAllByRole('listitem')).toHaveLength(1)
  expect(await within(list).findByText(/^#783/)).toBeInTheDocument()
  expect(within(list).queryByText(/^#123/)).not.toBeInTheDocument()

  expect(mock).toHaveBeenCalled()
})

it('can select alerts', async () => {
  // Need to have more than one open alert visible
  const alerts = [...openAlerts, ...openAlertsPageTwo]
  expect(alerts).toHaveLength(2)
  const mock = mockOpenAlertsRoute({
    alerts,
    nextCursor: '',
  })

  const {user} = await render()

  expect(mock).toHaveBeenCalled()

  const checkboxes = await screen.findAllByRole('checkbox', {name: /Select:/})
  expect(checkboxes).toHaveLength(2)

  await user.click(checkboxes[0]!)

  expect(await screen.findByText('1 of 3 selected')).toBeVisible()

  await user.click(checkboxes[1]!)

  expect(await screen.findByText('2 of 3 selected')).toBeVisible()

  await user.click(checkboxes[1]!)

  expect(await screen.findByText('1 of 3 selected')).toBeVisible()
})

// Skipping until we can avoid the tests timing out.
// See https://github.com/github/code-scanning/issues/15796 and https://github.com/github/github/issues/342308
it.skip('can paginate', async () => {
  mockOpenAlertsRoute()
  const {user} = await render()

  expect(
    await screen.findByRole('button', {
      name: 'Previous',
    }),
  ).toBeDisabled()

  const list = await screen.findByRole('list', {
    name: '3 alerts',
  })

  const nextPageMock = mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent('is:open')}&after=cursornext`,
    {
      ...defaultGetAlertsResponse(),
      alerts: openAlertsPageTwo,
      nextCursor: '',
      prevCursor: 'cursorprev',
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(
    await screen.findByRole('button', {
      name: 'Next',
    }),
  )

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(1)
  })
  expect(await within(list).findByText(/^#235/)).toBeInTheDocument()
  expect(within(list).queryByText(/^#123/)).not.toBeInTheDocument()
  expect(
    await screen.findByRole('button', {
      name: 'Next',
    }),
  ).toBeDisabled()

  expect(nextPageMock).toHaveBeenCalled()

  const prevPageMock = mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent('is:open')}&before=cursorprev`,
    {
      ...defaultGetAlertsResponse(),
      nextCursor: 'cursornext',
      prevCursor: '',
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(
    await screen.findByRole('button', {
      name: 'Previous',
    }),
  )

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(1)
  })
  expect(await within(list).findByText(/^#123/)).toBeInTheDocument()
  expect(within(list).queryByText(/^#235/)).not.toBeInTheDocument()
  expect(prevPageMock).toHaveBeenCalled()
})

it('does not show the create branch button when nothing is selected', async () => {
  mockOpenAlertsRoute()

  await render()
  expect(
    screen.queryByRole('button', {
      name: 'Create new branch',
    }),
  ).not.toBeInTheDocument()
})

it('does not show the create branch button when no create branch path is given', async () => {
  mockOpenAlertsRoute()

  const {user} = await render({
    createBranchPath: undefined,
  })

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  expect(
    screen.queryByRole('button', {
      name: 'Create new branch',
    }),
  ).not.toBeInTheDocument()
})

// Skipping until we can avoid the tests timing out.
// See https://github.com/github/code-scanning/issues/15796 and https://github.com/github/github/issues/342207
it.skip('can open the create branch dialog without autofixes', async () => {
  mockOpenAlertsRoute()

  const {user} = await render()
  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  const button = await getActionByName(user, 'Create new branch')
  await act(async () => {
    button.click()
  })

  expect(await screen.findByRole('dialog')).toHaveAccessibleName('Create new branch')
})

// Skipping until we can avoid the tests timing out.
// See https://github.com/github/code-scanning/issues/15796 and https://github.com/github/github/issues/340062
it.skip('disables create branch dialog when all selected alerts are fixed or dismissed', async () => {
  mockOpenAlertsRoute()
  const {user} = await render()

  mockFetch.mockRoute(
    `${alertsPath}?query=${encodeURIComponent('is:closed')}`,
    {
      ...defaultGetAlertsResponse(),
      alerts: closedAlerts,
    } satisfies GetAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(
    await screen.findByRole('link', {
      name: /^Closed/,
    }),
  )

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  expect(await getActionByName(user, 'Create new branch')).toBeDisabled()
})

it('can open the create branch dialog with autofix', async () => {
  mockOpenAlertsRoute({alerts: openAlertsWithFixes})
  const {user} = await render()

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  await user.click(
    await screen.findByRole('button', {
      name: 'Commit autofix',
    }),
  )

  await user.click(
    await screen.findByRole('listitem', {
      name: 'Commit to new branch',
    }),
  )

  expect(await screen.findByRole('dialog')).toHaveAccessibleName('Commit autofix to new branch')
})

it('can open the add to branch dialog with autofix', async () => {
  mockOpenAlertsRoute({alerts: openAlertsWithFixes})
  const {user} = await render()

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  await user.click(
    await screen.findByRole('button', {
      name: 'Commit autofix',
    }),
  )

  await user.click(
    await screen.findByRole('listitem', {
      name: 'Commit to existing branch',
    }),
  )

  expect(await screen.findByRole('dialog')).toHaveAccessibleName('Commit autofix to branch')
})

// Skipping until we can avoid the tests timing out.
// See https://github.com/github/code-scanning/issues/15796 and https://github.com/github/github/issues/338302
it.skip('clears the selection when a branch is created from the create branch dialog with checkout locally option', async () => {
  mockCreateBranch()
  mockOpenAlertsRoute()

  const {user} = await render()

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  for (const checkbox of await screen.findAllByRole('checkbox', {name: /Select:/})) {
    expect(checkbox).toBeChecked()
  }

  await user.click(await getActionByName(user, 'Create new branch'))

  const checkoutLocally = screen.getByLabelText('Checkout locally')
  await user.click(checkoutLocally)

  const createBranchDialog = await screen.findByRole('dialog')
  await user.click(await within(createBranchDialog).findByRole('button', {name: 'Create branch'}))

  const checkoutDialog = await screen.findByRole('dialog')
  await user.click(await within(checkoutDialog).findByRole('button', {name: 'Close'}))

  expect(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  ).not.toBeChecked()
  for (const checkbox of await screen.findAllByRole('checkbox', {name: /Select:/})) {
    expect(checkbox).not.toBeChecked()
  }
})

// Skipping until we can avoid the tests timing out.
// See https://github.com/github/code-scanning/issues/15796
it.skip('clears the selection when a branch is created from the create branch dialog with open in desktop option', async () => {
  mockCreateBranch()
  mockOpenAlertsRoute()

  const {user} = await render()

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  for (const checkbox of await screen.findAllByRole('checkbox', {name: /Select:/})) {
    expect(checkbox).toBeChecked()
  }

  await user.click(await getActionByName(user, 'Create new branch'))

  const createBranchDialog = await screen.findByRole('dialog')
  await user.click(await within(createBranchDialog).findByRole('radio', {name: 'Open branch with GitHub Desktop'}))
  await user.click(await within(createBranchDialog).findByRole('button', {name: 'Create branch'}))

  const openingBranchInDesktopDialog = await screen.findByRole('dialog')
  await user.click(await within(openingBranchInDesktopDialog).findByRole('button', {name: 'Close'}))

  expect(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  ).not.toBeChecked()
  for (const checkbox of await screen.findAllByRole('checkbox', {name: /Select:/})) {
    expect(checkbox).not.toBeChecked()
  }
})

it('creating a branch causes the alert list to refresh', async () => {
  mockCreateBranch()
  const openAlertsQuery = mockOpenAlertsRoute()

  const {user} = await render()

  expect(openAlertsQuery).toHaveBeenCalledTimes(1)

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  await user.click(await getActionByName(user, 'Create new branch'))

  const checkoutLocally = screen.getByLabelText('Checkout locally')
  await user.click(checkoutLocally)

  const createBranchDialog = await screen.findByRole('dialog')
  await user.click(await within(createBranchDialog).findByRole('button', {name: 'Create branch'}))

  const checkoutDialog = await screen.findByRole('dialog')
  await user.click(await within(checkoutDialog).findByRole('button', {name: 'Close'}))

  expect(openAlertsQuery).toHaveBeenCalledTimes(2)
})
