import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {SecurityCampaignFormTestWrapper} from '@github-ui/security-campaigns-shared/test-utils/SecurityCampaignFormTestWrapper'
import {
  SecurityCampaignOpenFormContents,
  type SecurityCampaignOpenFormContentsProps,
} from '../../components/SecurityCampaignOpenFormContents'

const defaultProps: SecurityCampaignOpenFormContentsProps = {
  organizationLogin: 'github',
  maxManagers: 10,
}

const render = async (props: Partial<SecurityCampaignOpenFormContentsProps> = {}) => {
  return reactRender(<SecurityCampaignOpenFormContents {...defaultProps} {...props} />, {
    wrapper: SecurityCampaignFormTestWrapper,
  })
}

beforeEach(() => {
  jest.clearAllMocks()
})

test('renders the form', async () => {
  render()

  expect(screen.getAllByRole('textbox')).toHaveLength(3)
  expect(screen.getByRole('textbox', {name: 'Campaign name *'})).toBeInTheDocument()
  expect(screen.getByRole('textbox', {name: 'Short description *'})).toBeInTheDocument()
  expect(screen.getByRole('textbox', {name: 'Contact link'})).toBeInTheDocument()
  expect(screen.getByLabelText(/date picker/i)).toBeInTheDocument()
  expect(
    screen.getByRole('button', {
      name: '@monalisa, Campaign managers*',
    }),
  ).toBeInTheDocument()

  expect(
    screen.getByRole('heading', {
      name: 'Managing',
    }),
  ).toBeInTheDocument()
})

test('does not include automation header when no feature flags are enabled', () => {
  render()

  expect(
    screen.queryByRole('heading', {
      name: 'Automation',
    }),
  ).not.toBeInTheDocument()
})

test('includes issues field when feature flag is enabled', () => {
  render({
    showGenerateIssues: true,
  })

  expect(
    screen.getByRole('heading', {
      name: 'Automation',
    }),
  ).toBeInTheDocument()
  expect(screen.getByRole('checkbox', {name: 'Create repository issues for this campaign'})).toBeInTheDocument()
})

test('includes issues field with count when count is given', () => {
  render({
    showGenerateIssues: true,
    repositoriesWithIssuesCount: 6723,
  })

  expect(
    screen.getByRole('checkbox', {name: 'Create up to 6,723 repository issues for this campaign'}),
  ).toBeInTheDocument()
})

test('correctly pluralizes 1 issue', () => {
  render({
    showGenerateIssues: true,
    repositoriesWithIssuesCount: 1,
  })

  expect(screen.getByRole('checkbox', {name: 'Create up to 1 repository issue for this campaign'})).toBeInTheDocument()
})

test('includes pull requests field when feature flag is enabled', () => {
  render({
    showAutofixPullRequests: true,
  })

  expect(
    screen.getByRole('heading', {
      name: 'Automation',
    }),
  ).toBeInTheDocument()
  expect(screen.getByRole('checkbox', {name: 'Generate pull requests using Copilot Autofix'})).toBeInTheDocument()
})

test('includes pull requests field with count when count is given', () => {
  render({
    showAutofixPullRequests: true,
    repositoriesWithPullRequestsCount: 8236,
  })

  expect(
    screen.getByRole('checkbox', {name: 'Generate up to 8,236 pull requests using Copilot Autofix'}),
  ).toBeInTheDocument()
})

test('correctly pluralizes 1 pull requests', () => {
  render({
    showAutofixPullRequests: true,
    repositoriesWithPullRequestsCount: 1,
  })

  expect(
    screen.getByRole('checkbox', {name: 'Generate up to 1 pull request using Copilot Autofix'}),
  ).toBeInTheDocument()
})

test('includes both issues and pull requests fields when both feature flags are enabled', () => {
  render({
    showGenerateIssues: true,
    showAutofixPullRequests: true,
    repositoriesWithIssuesCount: 357,
    repositoriesWithPullRequestsCount: 783,
  })

  expect(
    screen.getByRole('heading', {
      name: 'Automation',
    }),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('checkbox', {name: 'Create up to 357 repository issues for this campaign'}),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('checkbox', {name: 'Generate up to 783 pull requests using Copilot Autofix'}),
  ).toBeInTheDocument()
})
