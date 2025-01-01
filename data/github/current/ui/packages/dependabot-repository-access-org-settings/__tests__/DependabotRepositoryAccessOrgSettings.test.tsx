import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DependabotRepositoryAccessOrgSettings} from '../DependabotRepositoryAccessOrgSettings'
import {sampleRepos, getDependabotRepositoryAccessOrgSettingsProps} from './utils/mock-data'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'

const server = setupServer()

function seedServer() {
  const {promise: accessLevelChangedAwaiter, resolve: resolveAccessLevelChanged} = Promise.withResolvers<string>()
  const {promise: allowedReposChangedAwaiter, resolve: resolveAllowedReposChanged} = Promise.withResolvers<number[]>()

  server.use(
    http.put('/set-repository-access', async info => {
      const requestBodyJson = await info.request.json()
      if (typeof requestBodyJson !== 'object' || !requestBodyJson || !('accessLevel' in requestBodyJson)) {
        return HttpResponse.json({}, {status: 400})
      }

      resolveAccessLevelChanged(requestBodyJson['accessLevel'])
      return HttpResponse.json({})
    }),
    http.put('/set-allowed-repositories', async info => {
      const requestBodyJson = await info.request.json()
      if (typeof requestBodyJson !== 'object' || !requestBodyJson || !('repositoryIds' in requestBodyJson)) {
        return HttpResponse.json({}, {status: 400})
      }

      resolveAllowedReposChanged(requestBodyJson['repositoryIds'])
      return HttpResponse.json({})
    }),
    http.get('/repositories/picker/search', () => {
      return HttpResponse.json({
        items: sampleRepos,
        totalCount: sampleRepos.length,
      })
    }),
    http.get(`/repositories/picker/definitions`, () => {
      return HttpResponse.json({definitions: []})
    }),
  )

  return {accessLevelChangedAwaiter, allowedReposChangedAwaiter}
}

describe('dependabot-repository-access-org-settings', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    server.resetHandlers()
  })
  afterAll(() => {
    server.close()
  })

  test('Renders the DependabotRepositoryAccessOrgSettings', () => {
    const props = getDependabotRepositoryAccessOrgSettingsProps()
    render(<DependabotRepositoryAccessOrgSettings {...props} />)

    expect(screen.getByTestId('dependabot-repository-access-selector')).toBeInTheDocument()
    expect(screen.getByTestId('dependabot-allowed-repository-selector')).toBeInTheDocument()
  })

  test('Does not render default access selection if an update URL is not provided', () => {
    const props = getDependabotRepositoryAccessOrgSettingsProps()
    delete props['setRepositoryAccessUrl']
    render(<DependabotRepositoryAccessOrgSettings {...props} />)

    expect(screen.queryByTestId('dependabot-repository-access-selector')).not.toBeInTheDocument()
    expect(screen.getByTestId('dependabot-allowed-repository-selector')).toBeInTheDocument()
  })

  test('Updates the access level when a new access level is selected', async () => {
    const {accessLevelChangedAwaiter} = seedServer()

    const props = getDependabotRepositoryAccessOrgSettingsProps()
    const {user} = render(<DependabotRepositoryAccessOrgSettings {...props} />)

    const accessSelector = screen.getByRole('button', {name: 'Public repositories only'})
    expect(accessSelector).toBeInTheDocument()

    await user.click(accessSelector)

    const internalOption = screen.getByText('Public and internal repositories only')
    expect(internalOption).toBeInTheDocument()

    await user.click(internalOption)

    const selectedLevel = await accessLevelChangedAwaiter
    expect(selectedLevel).toEqual('internal')

    expect(screen.getByRole('button', {name: 'Public and internal repositories only'})).toBeInTheDocument()
  })

  test('Updates the allowed repositories when a new selection is made', async () => {
    const {allowedReposChangedAwaiter} = seedServer()

    const props = getDependabotRepositoryAccessOrgSettingsProps()
    const {user} = render(<DependabotRepositoryAccessOrgSettings {...props} />)

    const allowedReposSelector = screen.getByRole('button', {name: 'Select repositories'})
    expect(allowedReposSelector).toBeInTheDocument()

    await user.click(allowedReposSelector)

    const dialog = screen.getByRole('dialog')
    const smileOption = within(dialog).getByRole('option', {name: 'smile'})
    await user.click(smileOption)

    const orangeOption = within(dialog).getByRole('option', {name: 'orange'})
    await user.click(orangeOption)

    const selectButton = screen.getByRole('button', {name: 'Select (2)'})
    expect(selectButton).toBeInTheDocument()

    await user.click(selectButton)

    const selectedRepoIds = await allowedReposChangedAwaiter
    expect(selectedRepoIds.sort()).toEqual([2, 3])

    expect(screen.getByRole('button', {name: 'Internal repository: 2 repositories selected'})).toBeInTheDocument()
  })
})
