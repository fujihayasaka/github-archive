import {screen} from '@testing-library/react'
import {noop} from '@github-ui/noop'
import {getSafeConfig} from '../utils/option-config'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import {TemplateList} from '../TemplateList'
import type {TemplateListQuery} from './__generated__/TemplateListQuery.graphql'

const initialIssueTemplates = [
  {
    __id: '4',
    about: 'This is an issue template 01',
    name: 'Bug (Template)',
    filename: 'bug-01.md',
  },
  {
    __id: '5',
    about: 'This is an issue template 02',
    name: 'Design (Template)',
    filename: 'design.md',
  },
  {
    __id: '6',
    about: 'This is an issue template 03',
    name: 'Epic (Template)',
    filename: 'epic.md',
  },
]
const initialIssueForms = [
  {
    __id: '1',
    description: 'This is an issue form',
    name: 'Bug (Form)',
    filename: 'bug-02.yml',
  },
  {
    __id: '2',
    description: 'This is an issue form',
    name: 'Feature Request (Form)',
    filename: 'feature-request.yml',
  },
  {
    __id: '3',
    description: 'This is an issue form for a ',
    name: 'Task (Form)',
    filename: 'task.yml',
  },
]
const initialContactLinks = [
  {
    __id: '7',
    name: 'Contact Link 1',
    about: 'Description for contact link 1',
    url: 'https://example.com/contact1',
  },
  {
    __id: '8',
    name: 'Contact Link 2',
    about: 'Description for contact link 2',
    url: 'https://example.com/contact2',
  },
]

const setup = ({
  issueForms,
  issueTemplates,
  contactLinks,
  hasAnyTemplates = true,
  isBlankIssuesEnabled = true,
  isSecurityPolicyEnabled = true,
  canBypassTemplateSelection = true,
  navigate = noop,
}: {
  issueForms: typeof initialIssueForms
  issueTemplates: typeof initialIssueTemplates
  contactLinks: typeof initialContactLinks
  hasAnyTemplates: boolean
  isBlankIssuesEnabled: boolean
  isSecurityPolicyEnabled: boolean
  canBypassTemplateSelection: boolean
  navigate?: (url: string) => void
}) => {
  const {relayMockEnvironment} = renderRelay<{templateListQuery: TemplateListQuery}>(
    ({queryData}) => {
      const config = {
        navigate,
        canBypassTemplateSelection,
      }
      return (
        <IssueCreateContextProvider optionConfig={getSafeConfig(config)} preselectedData={undefined}>
          <TemplateList repository={queryData.templateListQuery.repository!} onTemplateSelected={noop} />
        </IssueCreateContextProvider>
      )
    },
    {
      relay: {
        queries: {
          templateListQuery: {
            type: 'fragment',
            query: graphql`
              query TemplateListQuery @relay_test_operation {
                repository(owner: "owner", name: "repo") {
                  ...TemplateList
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Repository() {
            return {
              isBlankIssuesEnabled,
              isSecurityPolicyEnabled,
              securityPolicyUrl: 'https://example.com/security',
              issueForms,
              issueTemplates,
              contactLinks,
              hasAnyTemplates,
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  return relayMockEnvironment
}

test('renders issue forms and templates in combined, ordered list', () => {
  setup({
    issueForms: initialIssueForms,
    issueTemplates: initialIssueTemplates,
    contactLinks: [],
    hasAnyTemplates: true,
    isBlankIssuesEnabled: true,
    canBypassTemplateSelection: true,
    isSecurityPolicyEnabled: true,
  })

  const templateItems = screen.getAllByText(/(Template|Form|Blank)/)
  const templateItemNames = templateItems.map(title => title.textContent)
  expect(templateItemNames).toEqual([
    'Templates and forms',
    'Bug (Template)',
    'Bug (Form)',
    'Design (Template)',
    'Epic (Template)',
    'Feature Request (Form)',
    'Task (Form)',
    'Blank issue',
  ])
})

test('renders security policy item when enabled and when repo has templates', () => {
  setup({
    issueForms: initialIssueForms,
    issueTemplates: initialIssueTemplates,
    contactLinks: [],
    hasAnyTemplates: true,
    isBlankIssuesEnabled: true,
    canBypassTemplateSelection: true,
    isSecurityPolicyEnabled: true,
  })

  expect(screen.getByText('Report a security vulnerability')).toBeInTheDocument()
})

test('does not render security policy item without templates', () => {
  setup({
    issueForms: [],
    issueTemplates: [],
    contactLinks: [],
    hasAnyTemplates: false,
    isBlankIssuesEnabled: false,
    canBypassTemplateSelection: true,
    isSecurityPolicyEnabled: true,
  })

  expect(screen.queryByText('Report a security vulnerability')).not.toBeInTheDocument()
})

test('renders external link items when contact links are provided', () => {
  setup({
    issueForms: [],
    issueTemplates: [],
    contactLinks: initialContactLinks,
    hasAnyTemplates: true,
    isBlankIssuesEnabled: false,
    canBypassTemplateSelection: true,
    isSecurityPolicyEnabled: true,
  })

  expect(screen.getByText('Contact Link 1')).toBeInTheDocument()
  expect(screen.getByText('Contact Link 2')).toBeInTheDocument()
})

test('renders no templates message when no templates are available', () => {
  setup({
    issueForms: [],
    issueTemplates: [],
    contactLinks: [],
    hasAnyTemplates: false,
    isBlankIssuesEnabled: false,
    canBypassTemplateSelection: true,
    isSecurityPolicyEnabled: true,
  })

  expect(screen.getByText('No templates available for the current repository')).toBeInTheDocument()
})

test('navigates to first template if there is only 1 and blank issues is disabled and the config canBypassTemplateSelection is true', () => {
  const navigate = jest.fn()
  setup({
    issueForms: [],
    issueTemplates: [initialIssueTemplates[0]!],
    contactLinks: [],
    hasAnyTemplates: true,
    isBlankIssuesEnabled: false,
    canBypassTemplateSelection: true,
    isSecurityPolicyEnabled: false,
    navigate,
  })
  expect(navigate).toHaveBeenCalled()
})

test('does no navigates to first template if there is only 1 and blank issues is disabled and the config canBypassTemplateSelection is false', () => {
  const navigate = jest.fn()
  setup({
    issueForms: [],
    issueTemplates: [initialIssueTemplates[0]!],
    contactLinks: [],
    hasAnyTemplates: true,
    isBlankIssuesEnabled: false,
    canBypassTemplateSelection: false,
    isSecurityPolicyEnabled: false,
    navigate,
  })
  expect(navigate).not.toHaveBeenCalled()
})
