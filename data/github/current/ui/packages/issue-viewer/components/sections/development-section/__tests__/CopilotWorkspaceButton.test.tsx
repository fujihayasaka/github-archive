import {screen} from '@testing-library/react'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {renderRelay} from '@github-ui/relay-test-utils'
import {Suspense} from 'react'
import {CopilotWorkspaceButton, type CopilotWorkspaceButtonProps} from '../CopilotWorkspaceButton'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {ThemeProvider} from '@primer/react'
import type {User} from '@github-ui/react-core/test-utils'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  ssrSafeWindow: {
    ...jest.requireActual('@github-ui/ssr-utils').ssrSafeWindow,
    location: {
      href: 'https://workspace.githubapp.com/',
    },
  },
}))

function setup({copilotWorkspaceUrl}: Partial<CopilotWorkspaceButtonProps>) {
  const {relayMockEnvironment, user} = renderRelay(
    () => {
      return (
        <ThemeProvider>
          <Suspense fallback="Loading...">
            <CopilotWorkspaceButton
              copilotWorkspaceUrl={copilotWorkspaceUrl ?? 'https://copilot-workspace.github.com/orgA/repoA/issues/1'}
            />
          </Suspense>
        </ThemeProvider>
      )
    },
    {
      relay: {
        queries: {
          topRepositories: {
            type: 'preloaded',
            query: TopRepositories,
            variables: {topRepositoriesFirst: 10, hasIssuesEnabled: null, owner: null},
          },
        },
        mockResolvers: {
          RepositoryConnection() {
            return {
              edges: [
                {node: buildRepository({owner: 'orgA', name: 'repoA'})},
                {node: buildRepository({owner: 'orgA', name: 'repoB'})},
                {node: buildRepository({owner: 'orgB', name: 'repoC'})},
              ],
            }
          },
        },
      },
    },
  )
  return {environment: relayMockEnvironment, user}
}

const openRepositoryPicker = (user: User) => {
  const repoButton = screen.getByRole('button', {
    name: 'Select code repository',
  })

  user.click(repoButton)
}

test('renders repositories when user clicks on the dropdown button', async () => {
  const {user} = setup({})

  openRepositoryPicker(user)

  const options = await screen.findAllByRole('option')

  expect(options).toHaveLength(3)
  expect(options[0]).toHaveTextContent('orgA/repoA')
})

test('opens issue with selected code repository in CopilotWorkspace', async () => {
  const copilotWorkspaceUrl = 'https://workspace.githubapp.com/orgA/repoA/issues/1'
  const {user} = setup({copilotWorkspaceUrl})

  openRepositoryPicker(user)

  const options = await screen.findAllByRole('option')

  expect(options).toHaveLength(3)
  expect(options[1]).toHaveTextContent('orgA/repoB')

  await user.click(options[1]!)

  const newUrl = new URL(copilotWorkspaceUrl, ssrSafeWindow?.location.href)
  newUrl.searchParams.set('codeOwner', 'orgA')
  newUrl.searchParams.set('codeRepo', 'repoB')

  expect(ssrSafeWindow?.location.href).toEqual(newUrl.href)
})

function buildRepository({name, owner}: {name: string; owner: string}) {
  return {
    id: mockRelayId(),
    name,
    owner: {
      login: owner,
    },
    isPrivate: false,
    isArchived: false,
    __typename: 'Repository',
  }
}
