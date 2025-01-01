import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useFetchCustomCopilots, useFetchVisibilitySettings} from '@github-ui/custom-copilots/hooks'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {useUpsertCopilotSpace} from '../hooks/use-upsert-copilot-space'
import {SpaceVisibilityDialog} from '../SpaceVisibilityDialog'

const userEvent = setupUserEvent()

jest.mock('@github-ui/custom-copilots/hooks', () => {
  const originalModule = jest.requireActual('@github-ui/custom-copilots/hooks')
  return {
    __esModule: true,
    ...originalModule,
    useFetchCustomCopilots: jest.fn(),
    useFetchVisibilitySettings: jest.fn(),
  }
})

jest.mock('../hooks/use-upsert-copilot-space', () => {
  return {
    __esModule: true,
    useUpsertCopilotSpace: jest.fn(),
  }
})

describe('SpaceVisibilityDialog', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders the SpaceVisibilityDialog', () => {
    renderSpaceVisibilityDialog({id: 42})

    expect(screen.getByText('Share this space')).toBeVisible()
    expect(screen.getByRole('button', {name: 'Copy link'})).toBeVisible()
  })

  test('changes the space visibility', async () => {
    const mockUpsertCopilotSpace = jest.fn().mockResolvedValue({})

    renderSpaceVisibilityDialog({id: 42, owner: 'spacecorp'}, {}, mockUpsertCopilotSpace)

    await waitFor(() => {
      expect(screen.queryByText('Loading space information...')).not.toBeInTheDocument()
    })

    const visibilityButton = screen.getByRole('button', {name: /Read/})
    await userEvent.click(visibilityButton)
    expect(screen.getByRole('menu')).toBeVisible()

    const noAccessOption = screen.getByRole('menuitemradio', {name: 'No access'})
    await userEvent.click(noAccessOption)

    expect(mockUpsertCopilotSpace).toHaveBeenCalledWith({
      visibility: 'private',
    })
  })

  test('disable dropdown if not editable', async () => {
    renderSpaceVisibilityDialog({id: 42, owner: 'spacecorp'}, {editable: false})

    await waitFor(() => {
      expect(screen.queryByText('Loading space information...')).not.toBeInTheDocument()
    })

    expect(screen.getByText('Read')).toBeVisible()

    expect(screen.queryByRole('button', {name: /Read/})).not.toBeInTheDocument()

    await userEvent.click(screen.getByText('Read'))
    expect(screen.queryByRole('menu')).not.toBeInTheDocument()
  })

  test('disable copy button if not shared', async () => {
    renderSpaceVisibilityDialog({id: 42, owner: 'spacecorp'}, {visibility: 'private'})

    await waitFor(() => {
      expect(screen.queryByText('Loading space information...')).not.toBeInTheDocument()
    })

    expect(screen.getByText('No access')).toBeVisible()
    const copyLinkButton = screen.getByRole('button', {name: 'Copy link'})
    expect(copyLinkButton).toBeDisabled()
  })

  test('copies the link when clicked', async () => {
    renderSpaceVisibilityDialog({id: 42})

    await waitFor(() => {
      expect(screen.queryByText('Loading space information...')).not.toBeInTheDocument()
    })

    const copyLinkButton = screen.getByRole('button', {name: 'Copy link'})

    await userEvent.click(copyLinkButton)
    await expect(navigator.clipboard.readText()).resolves.toEqual('http://localhost/copilot/spaces/42')

    expect(await screen.findByText('Link copied')).toBeVisible()
  })

  test('supports the owner/number url format', async () => {
    renderSpaceVisibilityDialog({id: 42, owner: 'spacecorp'})

    await waitFor(() => {
      expect(screen.queryByText('Loading space information...')).not.toBeInTheDocument()
    })

    expect(screen.getByText('Share this space')).toBeVisible()
    expect(screen.getByRole('button', {name: 'Copy link'})).toBeVisible()

    const copyLinkButton = screen.getByRole('button', {name: 'Copy link'})

    await userEvent.click(copyLinkButton)
    await expect(navigator.clipboard.readText()).resolves.toEqual('http://localhost/copilot/spaces/spacecorp/42')
  })

  test('displays correct footer text', () => {
    renderSpaceVisibilityDialog({id: 42})

    expect(screen.getByText('This space may include private content. Viewers need content access.')).toBeVisible()
  })

  test('displays base role text', () => {
    renderSpaceVisibilityDialog({id: 42})

    expect(screen.getByText('Base role')).toBeVisible()
  })

  test('displays organization name in visibility settings', async () => {
    renderSpaceVisibilityDialog({id: 42})

    await waitFor(() => {
      expect(screen.queryByText('Loading space information...')).not.toBeInTheDocument()
    })

    expect(screen.getByText('spacecorp')).toBeVisible()
    expect(screen.getByText('(owner)')).toBeVisible()
  })

  describe('member count functionality', () => {
    const memberCountCases = [
      {orgName: 'org-count-test-1', count: 42, label: '42 people'},
      {orgName: 'org-count-test-2', count: 1, label: '1 person'},
      {orgName: 'org-count-test-3', count: 5, label: '5 people'},
    ]

    test('shows loading state for member count initially and then displays count', async () => {
      const case0 = memberCountCases[0]!
      mockFetch.mockRoute(`/copilot/spaces/${case0.orgName}/42/settings/visibility`, {memberCount: case0.count})
      ;(useFetchVisibilitySettings as jest.Mock).mockReturnValueOnce({data: null, isLoading: true, error: false})
      renderSpaceVisibilityDialog(
        {id: 42, owner: case0.orgName},
        {owner: case0.orgName, ownerDisplayName: case0.orgName},
      )
      expect(screen.getByText('Organization')).toBeVisible()
      ;(useFetchVisibilitySettings as jest.Mock).mockReturnValue({
        data: {memberCount: case0.count},
        isLoading: false,
        error: false,
      })
      renderSpaceVisibilityDialog(
        {id: 42, owner: case0.orgName},
        {owner: case0.orgName, ownerDisplayName: case0.orgName},
      )
      expect(await screen.findByText(case0.label)).toBeVisible()
    })

    for (const mc of memberCountCases) {
      test(`displays correct form for ${mc.count} member(s)`, async () => {
        mockFetch.mockRoute(`/copilot/spaces/${mc.orgName}/42/settings/visibility`, {memberCount: mc.count})
        ;(useFetchVisibilitySettings as jest.Mock).mockReturnValue({
          data: {memberCount: mc.count},
          isLoading: false,
          error: false,
        })
        renderSpaceVisibilityDialog({id: 42, owner: mc.orgName}, {owner: mc.orgName, ownerDisplayName: mc.orgName})
        expect(await screen.findByText(mc.label)).toBeVisible()
      })
    }

    test('uses cached values when available', async () => {
      const orgName = 'org-count-test-4'
      const spy = jest.spyOn(mockFetch, 'fetch')
      mockFetch.mockRoute(`/copilot/spaces/${orgName}/42/settings/visibility`, {memberCount: 10})
      ;(useFetchVisibilitySettings as jest.Mock).mockReturnValue({
        data: {memberCount: 10},
        isLoading: false,
        error: false,
      })
      const {unmount} = renderSpaceVisibilityDialog(
        {id: 42, owner: orgName},
        {owner: orgName, ownerDisplayName: orgName},
      )
      await waitFor(() => {
        expect(screen.getByText('10 people')).toBeVisible()
      })
      const fetchCallCount = spy.mock.calls.length
      unmount()
      renderSpaceVisibilityDialog({id: 42, owner: orgName}, {owner: orgName, ownerDisplayName: orgName})
      expect(screen.getByText('10 people')).toBeVisible()
      expect(spy.mock.calls.length).toBe(fetchCallCount)
      spy.mockRestore()
    })

    test('handles API errors gracefully', async () => {
      const orgName = 'org-count-test-5'
      ;(useFetchVisibilitySettings as jest.Mock).mockReturnValue({data: null, isLoading: false, error: true})
      mockFetch.mockRoute(`/copilot/spaces/${orgName}/42/settings/visibility`, {}, {ok: false, status: 500})
      renderSpaceVisibilityDialog({id: 42, owner: orgName}, {owner: orgName, ownerDisplayName: orgName})
      await waitFor(() => {
        expect(screen.getByText('Organization')).toBeVisible()
      })
      expect(screen.queryByText(/\d+ people/)).not.toBeInTheDocument()
    })
  })

  function renderSpaceVisibilityDialog(id: CustomCopilotId, props = {}, mockUpsertFn?: jest.Mock) {
    const customCopilots = [
      getCustomCopilotMock({
        id: 42,
        oldId: 42,
        owner: 'spacecorp',
        ownerDisplayName: 'spacecorp',
        ownerIsOrg: true,
        visibility: 'org_public' as const,
        editable: true,
        ...props,
      }),
    ]

    ;(useFetchCustomCopilots as jest.Mock).mockReturnValue({
      data: customCopilots,
      isLoading: false,
    })
    ;(useFetchVisibilitySettings as jest.Mock).mockReturnValue({
      data: {
        memberCount:
          id.owner === 'org-count-test-1'
            ? 42
            : id.owner === 'org-count-test-2'
              ? 1
              : id.owner === 'org-count-test-3'
                ? 5
                : id.owner === 'org-count-test-4'
                  ? 10
                  : null,
      },
      isLoading: false,
      error: id.owner === 'org-count-test-5', // For the error test case
    })

    const upsertSpaceMock = mockUpsertFn || jest.fn().mockResolvedValue({})

    ;(useUpsertCopilotSpace as jest.Mock).mockReturnValue({
      upsertCopilotSpace: upsertSpaceMock,
      isPending: false,
    })

    return render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} customCopilots={customCopilots}>
        <SpaceVisibilityDialog closeDialog={() => {}} customCopilotId={id} />
      </CopilotChatProvider>,
    )
  }
})
