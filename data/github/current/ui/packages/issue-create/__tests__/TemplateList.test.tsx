import {render, screen} from '@testing-library/react'
import {TemplateList} from '../TemplateList'
import {noop} from '@github-ui/noop'
import {getDefaultConfig} from '../utils/option-config'
import {IssueCreateContextProvider} from '../contexts/IssueCreateContext'
import {isFeatureEnabled} from '@github-ui/feature-flags'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

const mockTemplates = {
  isBlankIssuesEnabled: true,
  isSecurityPolicyEnabled: true,
  issueForms: [
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
  ],
  issueTemplates: [
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
  ],
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const WrappedList = ({templates}: {templates: any}) => {
  return (
    <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={undefined}>
      <TemplateList onTemplateSelected={noop} templates={templates} />
    </IssueCreateContextProvider>
  )
}

test('renders issue forms and templates in combined, ordered list', () => {
  // Mock the issues_react_combined_template_list feature flag to be enabled
  mockIsFeatureEnabled.mockReturnValue(true)

  const {container} = render(<WrappedList templates={mockTemplates} />)

  // Expect all elements to be in the correct order
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  const templateItems = [...container.getElementsByClassName('actionListTitle')]
  const templateItemNames = templateItems.map(title => title.textContent)
  expect(templateItemNames).toEqual([
    'Bug (Template)',
    'Bug (Form)',
    'Design (Template)',
    'Epic (Template)',
    'Feature Request (Form)',
    'Task (Form)',
    'Blank issue',
  ])
})

test('renders issue forms and templates separately with issues_react_combined_template_list feature flag disabled', () => {
  mockIsFeatureEnabled.mockReturnValue(false)

  const {container} = render(<WrappedList templates={mockTemplates} />)

  // Expect all elements to be in the correct order
  // eslint-disable-next-line testing-library/no-container, testing-library/no-node-access
  const templateItems = [...container.getElementsByClassName('actionListTitle')]
  const templateItemNames = templateItems.map(title => title.textContent)
  expect(templateItemNames).toEqual([
    'Bug (Form)',
    'Feature Request (Form)',
    'Task (Form)',
    'Bug (Template)',
    'Design (Template)',
    'Epic (Template)',
    'Blank issue',
  ])
})

test('renders security policy item when enabled and when repo has templates', () => {
  const templatesWithSecurityPolicy = {
    issueTemplates: [
      {
        __id: '1',
        about: 'This is a bug issue template',
        name: 'Bug',
        filename: 'bug.yml',
      },
    ],
    isSecurityPolicyEnabled: true,
    securityPolicyUrl: 'https://example.com/security',
  }

  render(<WrappedList templates={templatesWithSecurityPolicy} />)

  expect(screen.getByText('Report a security vulnerability')).toBeInTheDocument()
})

test('does not render security policy item without templates', () => {
  const templatesWithSecurityPolicy = {
    issueForms: [],
    issueTemplates: [],
    isSecurityPolicyEnabled: true,
    securityPolicyUrl: 'https://example.com/security',
  }

  render(<WrappedList templates={templatesWithSecurityPolicy} />)

  expect(screen.queryByText('Report a security vulnerability')).not.toBeInTheDocument()
})

test('renders external link items when contact links are provided', () => {
  const templatesWithContactLinks = {
    ...mockTemplates,
    contactLinks: [
      {
        ____id: '1',
        name: 'Contact Link 1',
        about: 'Description for contact link 1',
        url: 'https://example.com/contact1',
      },
      {
        ____id: '2',
        name: 'Contact Link 2',
        about: 'Description for contact link 2',
        url: 'https://example.com/contact2',
      },
    ],
  }

  render(<WrappedList templates={templatesWithContactLinks} />)

  expect(screen.getByText('Contact Link 1')).toBeInTheDocument()
  expect(screen.getByText('Contact Link 2')).toBeInTheDocument()
})

test('renders no templates message when no templates are available', () => {
  const emptyTemplates = {
    isBlankIssuesEnabled: false,
    isSecurityPolicyEnabled: false,
    issueForms: [],
    issueTemplates: [],
  }

  render(<WrappedList templates={emptyTemplates} />)

  expect(screen.getByText('No templates available for the current repository')).toBeInTheDocument()
})
