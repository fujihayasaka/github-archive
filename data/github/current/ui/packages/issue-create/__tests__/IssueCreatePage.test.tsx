import {renderRelay} from '@github-ui/relay-test-utils'
import {IssueCreatePage, type IssueCreatePageProps} from '../IssueCreatePage'
import {graphql} from 'relay-runtime'
import type {IssueCreatePageTestQuery} from './__generated__/IssueCreatePageTestQuery.graphql'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {act, fireEvent, screen} from '@testing-library/react'
import {MockPayloadGenerator} from 'relay-test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {TEST_IDS} from '../constants/test-ids'

const IssueCreatePageTestQuery = graphql`
  query IssueCreatePageTestQuery @relay_test_operation {
    repository(owner: "owner", name: "repo") {
      ...IssueCreatePage
    }
  }
`

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    ...jest.requireActual('@github-ui/use-navigate'),
    useNavigate: () => navigateFn,
  }
})

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

const issueTemplatePayloadMock = jest.fn()

const setup = (
  {...props}: Omit<IssueCreatePageProps, 'currentRepository'> = {
    initialMetadataValues: {},
    storageKeyPrefix: 'issue-create',
    pasteUrlsAsPlainText: false,
    useMonospaceFont: false,
    emojiSkinTonePreference: undefined,
    singleKeyShortcutsEnabled: true,
  },
) => {
  const {relayMockEnvironment} = renderRelay<{issueCreatePageQuery: IssueCreatePageTestQuery}>(
    ({queryData}) => {
      if (!queryData.issueCreatePageQuery.repository) {
        throw new Error('repository must be defined')
      }
      return <IssueCreatePage currentRepository={queryData.issueCreatePageQuery.repository} {...props} />
    },
    {
      relay: {
        queries: {
          issueCreatePageQuery: {
            type: 'fragment',
            query: IssueCreatePageTestQuery,
            variables: {},
          },
        },
        mockResolvers: {
          Repository() {
            return {
              id: 'R_1',
              databaseId: '1',
              name: 'repository',
              nameWithOwner: 'github/issues',
              owner: {
                login: 'github',
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
              issueTemplate: issueTemplatePayloadMock,
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  return relayMockEnvironment
}

describe('IssueCreatePage', () => {
  beforeAll(() => {
    mockedUseAppPayload.mockReturnValue({
      current_user: {
        avatarUrl: '',
        login: 'monalisa',
      },
    })
  })

  test('clicking save issue will navigate to new issue', async () => {
    const environment = setup()
    expect(screen.getByText('Create new issue')).toBeInTheDocument()
    expect(screen.getByText(`View monalisa's profile`)).toBeInTheDocument()

    // Fill required fields
    const titleInput = screen.getByLabelText('Add a title')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.input(titleInput, {target: {value: 'test title'}})

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

  test('clicking save issue will not navigate to new issue when click more is checked', async () => {
    const environment = setup()
    expect(screen.getByText('Create new issue')).toBeInTheDocument()
    expect(screen.getByText(`View monalisa's profile`)).toBeInTheDocument()

    // Fill required fields
    let titleInput = screen.getByLabelText('Add a title')
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.input(titleInput, {target: {value: 'test title'}})

    const createMoreCheck = screen.getByTestId(TEST_IDS.createMoreIssuesCheckbox)
    act(() => createMoreCheck.click())

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

    expect(navigateFn).not.toHaveBeenCalledWith('/github/issues/issues/1')

    titleInput = screen.getByLabelText('Add a title')
    expect(titleInput).toHaveValue('')
  })
})
