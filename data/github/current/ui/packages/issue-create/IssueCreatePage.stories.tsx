import type {Meta} from '@storybook/react'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {graphql} from 'relay-runtime'
import {IssueCreateContextProvider} from './contexts/IssueCreateContext'
import {getDefaultConfig} from './utils/option-config'
import {IssueCreatePage, type IssueCreatePageProps} from './IssueCreatePage'
import type {IssueCreatePageStoryQuery} from './__generated__/IssueCreatePageStoryQuery.graphql'
import type {UserHookPayload} from '@github-ui/use-user'

type IssueCreatePageQueries = {
  issueCreatePageQuery: IssueCreatePageStoryQuery
}

const currentUser: Partial<UserHookPayload['current_user']> = {
  name: 'Monalisa Octocat',
  avatarUrl: 'https://github.com/octocat.png',
  login: 'octocat',
}

const wrapped = (props: IssueCreatePageProps) => (
  <Wrapper appPayload={{current_user: currentUser}}>
    <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={undefined}>
      <IssueCreatePage {...props} />
    </IssueCreateContextProvider>
  </Wrapper>
)

const meta = {
  title: 'IssuesCreate/IssueCreatePage',
  component: wrapped,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof IssueCreatePage>

export default meta

const defaultArgs: Partial<typeof IssueCreatePage> = {
  initialMetadataValues: {},
  storageKeyPrefix: '',
  pasteUrlsAsPlainText: true,
  useMonospaceFont: true,
  emojiSkinTonePreference: true,
  singleKeyShortcutsEnabled: true,
}

export const IssueCreatePageExample = {
  decorators: [relayDecorator<typeof IssueCreatePage, IssueCreatePageQueries>],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        issueCreatePageQuery: {
          type: 'fragment',
          query: graphql`
            query IssueCreatePageStoryQuery @relay_test_operation {
              repository(owner: "owner", name: "name") {
                ...IssueCreatePage
              }
            }
          `,
          variables: {},
        },
      },
      mockResolvers: {
        Repository() {
          return {
            hasIssuesEnabled: false,
          }
        },
      },
      mapStoryArgs: ({queryData}) => ({
        currentRepository: queryData.issueCreatePageQuery.repository!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof IssueCreatePage, IssueCreatePageQueries>
