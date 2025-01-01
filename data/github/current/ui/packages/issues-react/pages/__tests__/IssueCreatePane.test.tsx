import {render} from '@github-ui/react-core/test-utils'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {act, fireEvent, screen} from '@testing-library/react'
import {useQueryLoader} from 'react-relay'
import type {OperationDescriptor} from 'relay-runtime'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import HyperlistAppWrapper from '../../test-utils/HyperlistAppWrapper'
import {IssueCreatePane} from '../issue-new/IssueCreatePane'
import {CurrentRepository} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerCurrentRepoQuery} from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'

const navigateFn = jest.fn()

jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: () => navigateFn,
}))

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

const IssueCreatePaneTestWrapper = () => {
  const [currentRepo, loadCurrentRepo, disposeCurrentRepo] =
    useQueryLoader<RepositoryPickerCurrentRepoQuery>(CurrentRepository)

  return (
    <IssueCreatePane
      currentRepoQueryRef={currentRepo}
      loadCurrentRepo={loadCurrentRepo}
      disposeCurrentRepo={disposeCurrentRepo}
    />
  )
}

test('clicking save issue will navigate to new issue', async () => {
  const environment = createMockEnvironment()

  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
    scoped_repository: {
      name: 'issues',
      owner: 'github',
    },
    current_user: {
      avatarUrl: '',
      login: 'monalisa',
    },
  })

  render(
    <HyperlistAppWrapper environment={environment}>
      <IssueCreatePaneTestWrapper />
    </HyperlistAppWrapper>,
  )

  await act(async () => {
    environment.mock.resolveMostRecentOperation((operation: OperationDescriptor) => {
      expect(operation.request.node.operation.name).toBe('RepositoryPickerCurrentRepoQuery')
      expect(operation.request.variables).toEqual({
        includeTemplates: true,
        name: 'issues',
        owner: 'github',
      })
      return MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          id: 'R_1',
          databaseId: '1',
          name: 'repository',
          nameWithOwner: 'organization/repository',
          owner: {
            login: 'organization',
          },
          isPrivate: false,
          isArchived: false,
          hasIssuesEnabled: true,
          slashCommandsEnabled: false,
          viewerCanPush: true,
          templateTreeUrl: 'template-url',
          viewerIssueCreationPermissions: {
            labelable: true,
            milestoneable: true,
            assignable: true,
            triageable: true,
            typeable: true,
          },
        }),
      })
    })
  })

  expect(screen.getByText('Create new issue')).toBeInTheDocument()
  expect(screen.getByText(`View monalisa's profile`)).toBeInTheDocument()

  // Choose template
  const blankTemplateButton = screen.getByRole('link', {name: /Blank issue/i})

  act(() => blankTemplateButton.click())

  // Fill required fields
  const titleInput = screen.getByLabelText('Add a title')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.change(titleInput, {target: {value: 'test title'}})

  expect(ssrSafeLocation.search).toBe('?template=Blank+issue')

  // Create issue
  const saveButton = screen.getByRole('button', {name: /create/i})

  navigateFn.mockClear()
  act(() => {
    saveButton.click()

    environment.mock.resolveMostRecentOperation(operation =>
      MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: 'I_1',
          number: 1,
          title: 'test title',
          url: 'issue1-url',
          repository: {
            name: 'issues',
            owner: {
              login: 'github',
            },
          },
        }),
      }),
    )
  })

  expect(navigateFn).toHaveBeenCalledWith('/github/issues/issues/1')
})
