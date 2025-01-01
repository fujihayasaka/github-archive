import type {Meta} from '@storybook/react'
import {noop} from '@github-ui/noop'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'relay-runtime'
import {TemplateListInternal, type TemplateListPaneInternalProps} from './TemplateListPane'
import type {TemplateListPaneNewStoryQuery} from './__generated__/TemplateListPaneNewStoryQuery.graphql'
import {IssueCreateContextProvider} from './contexts/IssueCreateContext'
import {getDefaultConfig} from './utils/option-config'

type TemplateListNewInternalQueries = {
  templateListPanQuery: TemplateListPaneNewStoryQuery
}

const wrapped = (props: TemplateListPaneInternalProps) => (
  <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={undefined}>
    <TemplateListInternal {...props} />
  </IssueCreateContextProvider>
)

const meta = {
  title: 'IssuesCreate/Template',
  component: wrapped,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof TemplateListInternal>

export default meta

const defaultArgs: Partial<typeof TemplateListInternal> = {
  onTemplateSelected: noop,
}

export const TemplateListNewInternalExample = {
  decorators: [relayDecorator<typeof TemplateListInternal, TemplateListNewInternalQueries>],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        templateListPanQuery: {
          type: 'fragment',
          query: graphql`
            query TemplateListPaneNewStoryQuery @relay_test_operation {
              repository(owner: "owner", name: "name") {
                ...TemplateListPane
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
        repository: queryData.templateListPanQuery.repository!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof TemplateListInternal, TemplateListNewInternalQueries>
