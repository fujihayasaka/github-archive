import {act, screen, waitFor, within} from '@testing-library/react'
import {render as reactRender, type User} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {createRepository, createSecurityCampaignAlert} from '../../test-utils/mock-data'
import {RepoAlertsList, type RepoAlertsListProps} from '../../components/RepoAlertsList'
import type {GetAlertsResponse} from '../../types/get-alerts-response'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {type Environment, RelayEnvironmentProvider} from 'react-relay'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {BannerProvider} from '@github-ui/role-assignments/banner-provider'

jest.setTimeout(15_000)

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
    alertCount: openAlerts.length + openAlertsPageTwo.length + closedAlerts.length,
    openCount: openAlerts.length + openAlertsPageTwo.length,
    closedCount: closedAlerts.length,
    openWithLinksCount: 0,
    nextCursor: 'cursornext',
    prevCursor: '',
    ...props,
  }
}

const mockCreateBranch = () => {
  mockFetch.mockRoute(
    '/github/security-campaigns/security/campaigns/5/branches',
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
      securityCampaignNumber={5}
      canCreateBranch
      canCloseAlerts
      delegatedAlertDismissalEnabled={false}
      {...props}
    />,
    {
      wrapper: ({children}: TestWrapperProps) => {
        return (
          <BannerProvider>
            <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
          </BannerProvider>
        )
      },
    },
  )

  // Wait for the alerts to load
  await waitFor(() => {
    expect(screen.getByTestId('alerts-list')).toBeInTheDocument()
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

// Timeout has been increased to 20 seconds because this is an integration test
it('can paginate', async () => {
  mockOpenAlertsRoute()
  const {user} = await render()

  expect(screen.queryByTestId('previous-button')).not.toBeInTheDocument()

  const list = screen.getByTestId('alerts-list')

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

  await user.click(await screen.findByTestId('next-button'))

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(1)
  })
  expect(await within(list).findByText(/^#235/)).toBeInTheDocument()
  expect(within(list).queryByText(/^#123/)).not.toBeInTheDocument()
  expect(screen.getByTestId('next-button')).toBeDisabled()

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

  await user.click(screen.getByTestId('previous-button'))

  await waitFor(() => {
    expect(within(list).getAllByRole('listitem')).toHaveLength(1)
  })
  expect(await within(list).findByText(/^#123/)).toBeInTheDocument()
  expect(within(list).queryByText(/^#235/)).not.toBeInTheDocument()
  expect(prevPageMock).toHaveBeenCalled()
}, 20_000)

it('does not show the create branch button when nothing is selected', async () => {
  mockOpenAlertsRoute()

  await render()
  expect(
    screen.queryByRole('button', {
      name: 'Create new branch',
    }),
  ).not.toBeInTheDocument()
})

it('does not show the create branch button when canCreateBranch is false', async () => {
  mockOpenAlertsRoute()

  const {user} = await render({
    canCreateBranch: false,
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

// Timeout has been increased to 20 seconds because this is an integration test
it('can open the create branch dialog without autofixes', async () => {
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
}, 20_000)

// Timeout has been increased to 20 seconds because this is an integration test
it('disables create branch dialog when all selected alerts are fixed or dismissed', async () => {
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
}, 20_000)

it('can open the create branch dialog with autofix', async () => {
  mockOpenAlertsRoute({alerts: openAlertsWithFixes})
  const {user} = await render()

  await user.click(
    await screen.findByRole('checkbox', {
      name: /Select all/,
    }),
  )

  await user.click(screen.getByText('Commit autofix'))

  await user.click(screen.getByText('Commit to new branch'))

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

  await user.click(screen.getByText('Commit autofix'))

  await user.click(screen.getByText('Commit to existing branch'))

  expect(await screen.findByRole('dialog')).toHaveAccessibleName('Commit autofix to branch')
})

// Timeout has been increased to 20 seconds because this is an integration test
it('clears the selection when a branch is created from the create branch dialog with checkout locally option', async () => {
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
  await user.click(await within(createBranchDialog).findByText('Create branch'))

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
}, 20_000)

// Timeout has been increased to 20 seconds because this is an integration test
it('clears the selection when a branch is created from the create branch dialog with open in desktop option', async () => {
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
  await user.click(await within(createBranchDialog).findByText('Open branch with GitHub Desktop'))
  await user.click(await within(createBranchDialog).findByText('Create branch'))

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
}, 20_000)

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
  await user.click(await within(createBranchDialog).findByText('Create branch'))

  const checkoutDialog = await screen.findByRole('dialog')
  await user.click(await within(checkoutDialog).findByRole('button', {name: 'Close'}))

  expect(openAlertsQuery).toHaveBeenCalledTimes(2)
}, 20_000)

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

describe('Assign to Copilot button', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('shows the Assign to Copilot button when feature flag is enabled and the selected alerts have fixes', async () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'code_scanning_agentic_autofix_padawan_integration')

    mockOpenAlertsRoute({alerts: openAlertsWithFixes})
    const {user} = await render()

    await user.click(await screen.findByRole('checkbox', {name: /Select all/}))

    expect(screen.getByRole('button', {name: /Assign to Copilot/})).toBeInTheDocument()
  })

  it('the Assign to Copilot button is disabled when feature flag is enabled but not all selected alerts have fixes', async () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'code_scanning_agentic_autofix_padawan_integration')

    mockOpenAlertsRoute({alerts: [...openAlerts, ...openAlertsWithFixes]})
    const {user} = await render()

    await user.click(await screen.findByRole('checkbox', {name: /Select all/}))

    const button = screen.getByRole('button', {name: /Assign to Copilot/})
    expect(button).toBeDisabled()
  })

  it('does not show the Assign to Copilot button when feature flag is disabled', async () => {
    mockUseFeatureFlag.mockImplementation(() => false)

    mockOpenAlertsRoute({alerts: openAlertsWithFixes})
    const {user} = await render()

    await user.click(await screen.findByRole('checkbox', {name: /Select all/}))

    expect(screen.queryByRole('button', {name: /Assign to Copilot/})).not.toBeInTheDocument()
  })
})
