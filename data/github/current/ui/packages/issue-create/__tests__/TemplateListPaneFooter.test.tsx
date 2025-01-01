import {screen} from '@testing-library/react'
import {getDefaultConfig} from '../utils/option-config'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'

import {renderRelay} from '@github-ui/relay-test-utils'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {TemplateListPaneFooterQuery} from './__generated__/TemplateListPaneFooterQuery.graphql'
import {graphql} from 'relay-runtime'
import {TemplateListPaneFooter} from '../TemplateListPaneFooter'

const setup = (typeable = true) => {
  const {relayMockEnvironment} = renderRelay<{templateListQuery: TemplateListPaneFooterQuery}>(
    ({queryData}) => (
      <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={undefined}>
        <TemplateListPaneFooter repository={queryData.templateListQuery.repository!} />
      </IssueCreateContextProvider>
    ),
    {
      relay: {
        queries: {
          templateListQuery: {
            type: 'fragment',
            query: graphql`
              query TemplateListPaneFooterQuery @relay_test_operation {
                repository(owner: "owner", name: "repo") {
                  ...TemplateListPaneFooter
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Repository() {
            return {
              viewerCanPush: true,
              viewerIssueCreationPermissions: {
                typeable,
                triageable: true,
              },
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  return relayMockEnvironment
}

test('renders the issue types copy when the viewer can access types', () => {
  setup(true)
  expect(screen.getByText('You can now add issue types to your forms and templates!')).toBeInTheDocument()
})

test('does not render the issue types copy when the viewer cannot access types', () => {
  setup(false)
  expect(screen.queryByText('You can now add issue types to your forms and templates!')).not.toBeInTheDocument()
})
